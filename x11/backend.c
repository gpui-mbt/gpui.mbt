#define _POSIX_C_SOURCE 200809L
#include "backend.h"
#include "../platform/linux_text/linux_text.h"
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/XKBlib.h>
#include <X11/Xatom.h>
#include <X11/cursorfont.h>
#include <errno.h>
#include <limits.h>
#include <math.h>
#include <poll.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/eventfd.h>
#include <time.h>
#include <unistd.h>
#include <xkbcommon/xkbcommon.h>
#include <xkbcommon/xkbcommon-compose.h>

#define QUEUE_CAPACITY 1024
#define CLIPBOARD_LIMIT (16 * 1024 * 1024)
#define CLIPBOARD_TIMEOUT_MS 3000
#define CLIPBOARD_CHUNK 32768
#define TRANSFER_CAPACITY 4
#define UNUSED(x) (void)(x)
struct direct_event_meta {
  int epoch, direct_origin, text_length, revoked;
  uint8_t text[GPUI_DIRECT_TEXT_MAX_BYTES + 1];
};
struct direct_key_state { int pressed, epoch, direct_origin, swallowed; };
struct selection_transfer {
  Window requestor;
  Atom property;
  uint8_t *bytes;
  size_t length, offset;
  long previous_mask;
  int64_t deadline;
};
struct host {
  int token, window, state, error, wake_fd;
  pthread_t owner;
  Display *display;
  Window xwindow;
  Colormap colormap;
  Atom wm_protocols, wm_delete, net_name, utf8, clipboard, targets, incr;
  Atom selection_property;
  Window selection_window;
  Cursor cursors[3];
  int cursor_kind, detectable_repeat, keyboard_focus_current;
  struct xkb_context *xkb;
  struct xkb_compose_table *compose_table;
  struct xkb_compose_state *compose;
  int direct_enabled, direct_epoch, direct_exhausted, direct_ever_enabled;
  struct direct_key_state direct_keys[GPUI_DIRECT_KEY_CAPACITY];
  double queue[QUEUE_CAPACITY][10];
  struct direct_event_meta direct_queue[QUEUE_CAPACITY];
  int read, count, seq, modifiers;
  double px, py;
  int width, height, scale, configured, frame;
  EGLDisplay egl;
  EGLContext context;
  EGLSurface egl_surface;
  EGLConfig config;
  GLuint program, mask_program;
  GLint color_uniform, mask_color_uniform, mask_sampler_uniform;
  uint8_t *frame_pixels;
  int frame_width, frame_height, frame_scale;
  uint8_t *clipboard_owned, *clipboard_result;
  size_t clipboard_owned_length, clipboard_result_length;
  int owns_clipboard, selection_wait, selection_done, selection_incr;
  int selection_status;
  Atom selection_target;
  struct selection_transfer transfers[TRANSFER_CAPACITY];
};
static struct host *active;
static pthread_mutex_t registry_mutex = PTHREAD_MUTEX_INITIALIZER;
static int next_host = 1, next_window = 1;
static int (*previous_xerror)(Display *, XErrorEvent *);
static int xerror_depth, stopping;
static struct host *error_host;
static int pump(struct host *h, int timeout);
static void release_window(struct host *h);

static int native_e2e_enabled(void) {
  const char *value = getenv("GPUI_NATIVE_E2E");
  return value && !strcmp(value, "1");
}
static int valid_size(int w, int h, int scale) {
  return w > 0 && h > 0 && scale > 0 && w <= 16384 / scale && h <= 16384 / scale;
}
static int64_t monotonic_milliseconds(void) {
  struct timespec t;
  if (clock_gettime(CLOCK_MONOTONIC, &t) || t.tv_sec < 0 || t.tv_nsec < 0 ||
      t.tv_nsec >= 1000000000 ||
      (uint64_t)t.tv_sec > (uint64_t)(INT64_MAX - t.tv_nsec / 1000000) / 1000)
    return -1;
  return (int64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}
static int check(int token, struct host **out) {
  pthread_mutex_lock(&registry_mutex);
  int s = !active || active->token != token ? GPUI_STALE :
          !pthread_equal(active->owner, pthread_self()) ? GPUI_WRONG_THREAD : GPUI_OK;
  if (!s) *out = active;
  pthread_mutex_unlock(&registry_mutex);
  return s;
}
static int window_check(int token, int window, struct host **out) {
  int s = check(token, out);
  return s ? s : ((*out)->window && (*out)->window == window ? GPUI_OK : GPUI_STALE);
}
static void event(struct host *h, int kind, double detail, double x, double y) {
  if (!h->window) return;
  if (h->count == QUEUE_CAPACITY || h->seq == INT_MAX) {
    h->error = GPUI_RESOURCE;
    return;
  }
  int slot = (h->read + h->count++) % QUEUE_CAPACITY;
  double *e = h->queue[slot];
  memset(&h->direct_queue[slot], 0, sizeof(h->direct_queue[slot]));
  e[0] = kind; e[1] = h->window; e[2] = ++h->seq; e[3] = h->scale;
  e[4] = h->width; e[5] = h->height; e[6] = x; e[7] = y;
  e[8] = detail; e[9] = h->modifiers;
}
#include "../platform/linux_renderer/utf8.inc.c"
static void reset_compose(struct host *h) {
  if (h->compose) xkb_compose_state_reset(h->compose);
}
static int advance_direct_epoch(struct host *h) {
  reset_compose(h);
  if (h->direct_exhausted || h->direct_epoch == INT_MAX) {
    h->direct_exhausted = 1; h->direct_enabled = 0;
    return GPUI_RESOURCE;
  }
  ++h->direct_epoch;
  return GPUI_OK;
}
static void reset_direct_text(struct host *h) {
  if (advance_direct_epoch(h)) h->error = GPUI_RESOURCE;
  h->direct_enabled = 0;
  memset(h->direct_keys, 0, sizeof(h->direct_keys));
}
static int require_direct_keyboard(struct host *h) {
  if (h->direct_exhausted) return GPUI_RESOURCE;
  if (h->state) return GPUI_STOPPING;
  return h->xkb && h->compose ? GPUI_OK : GPUI_UNSUPPORTED;
}
static void direct_key_record(struct host *h, int kind, xkb_keysym_t sym,
    uint32_t scalar, int epoch, int origin, int repeat) {
  int slot = (h->read + h->count) % QUEUE_CAPACITY, prior = h->count;
  event(h, kind, sym, scalar, repeat);
  if (h->count != prior) {
    h->direct_queue[slot].epoch = epoch;
    h->direct_queue[slot].direct_origin = origin;
  }
}
static void direct_text_record(struct host *h, const uint8_t *text, int length) {
  int slot = (h->read + h->count) % QUEUE_CAPACITY, prior = h->count;
  event(h, 13, length, 0, 0);
  if (h->count != prior) {
    struct direct_event_meta *m = &h->direct_queue[slot];
    m->epoch = h->direct_epoch; m->direct_origin = 1; m->text_length = length;
    memcpy(m->text, text, (size_t)length); m->text[length] = 0;
  }
}
static int modifiers(unsigned state) {
  return ((state & ShiftMask) ? 1 : 0) | ((state & ControlMask) ? 2 : 0) |
      ((state & Mod1Mask) ? 4 : 0) | ((state & Mod4Mask) ? 8 : 0);
}
/* XKB resolves the server's actual map/group/modifiers. libxkbcommon handles
 * locale compose only. XIM/preedit is deliberately not opened or advertised. */
static void keyboard_key(struct host *h, XKeyEvent *e, int pressed) {
  if (!h->keyboard_focus_current || h->state || h->error || e->keycode >= 256) return;
  KeySym symbol = NoSymbol;
  unsigned consumed = 0;
  if (!XkbLookupKeySym(h->display, (KeyCode)e->keycode, e->state, &consumed, &symbol)) return;
  h->modifiers = modifiers(e->state);
  uint32_t scalar = xkb_keysym_to_utf32((xkb_keysym_t)symbol);
  struct direct_key_state *key = &h->direct_keys[e->keycode];
  if (!pressed) {
    if (key->pressed && !key->swallowed)
      direct_key_record(h, 12, (xkb_keysym_t)symbol, scalar, key->epoch, key->direct_origin, 0);
    memset(key, 0, sizeof(*key));
    return;
  }
  int repeat = key->pressed;
  if (repeat && (key->epoch != h->direct_epoch || key->direct_origin != h->direct_enabled)) return;
  if (!repeat) {
    key->pressed = 1; key->epoch = h->direct_epoch;
    key->direct_origin = h->direct_enabled; key->swallowed = 0;
  }
  if (!h->direct_enabled) {
    direct_key_record(h, 11, (xkb_keysym_t)symbol, scalar, h->direct_epoch, 0, repeat);
    return;
  }
  if (require_direct_keyboard(h)) { h->error = GPUI_UNSUPPORTED; return; }
  uint8_t text[GPUI_DIRECT_TEXT_MAX_BYTES + 1];
  int length = 0, emit_key = 1;
  if (h->modifiers & (2 | 8)) {
    reset_compose(h);
  } else if (!(repeat && key->swallowed)) {
    enum xkb_compose_feed_result feed = xkb_compose_state_feed(h->compose, (xkb_keysym_t)symbol);
    enum xkb_compose_status status = xkb_compose_state_get_status(h->compose);
    if (feed == XKB_COMPOSE_FEED_ACCEPTED && status != XKB_COMPOSE_NOTHING) {
      emit_key = 0; key->swallowed = 1;
      if (status == XKB_COMPOSE_COMPOSED) {
        length = xkb_compose_state_get_utf8(h->compose, (char *)text, sizeof(text));
        reset_compose(h);
      } else if (status == XKB_COMPOSE_CANCELLED) reset_compose(h);
    } else {
      int n = xkb_keysym_to_utf8((xkb_keysym_t)symbol, (char *)text, sizeof(text));
      length = n > 0 ? n - 1 : 0;
    }
  } else emit_key = 0;
  if (length < 0 || length > GPUI_DIRECT_TEXT_MAX_BYTES) { h->error = GPUI_RESOURCE; return; }
  if (!direct_utf8_valid(text, length)) { h->error = GPUI_INVALID; return; }
  if (direct_has_control(text, length)) length = 0;
  int records = emit_key + (length > 0);
  if (records > QUEUE_CAPACITY - h->count || records > INT_MAX - h->seq) {
    h->error = GPUI_RESOURCE; return;
  }
  if (emit_key) direct_key_record(h, 11, (xkb_keysym_t)symbol, scalar, h->direct_epoch, 1, repeat);
  if (length) direct_text_record(h, text, length);
}

/* Xlib has process-global error handlers. Install a narrow, synchronous trap
 * only around requests that may race disappearing foreign clipboard windows
 * or native teardown. Restore the previous handler before returning to callers
 * and forward errors from other connections. No persistent handler or IO-error
 * override, global locale change, or XInitThreads call is made. */
static int xerror(Display *display, XErrorEvent *e) {
  if (error_host && display == error_host->display) {
    if (e->error_code == BadWindow && e->resourceid != error_host->xwindow) return 0;
    error_host->error = GPUI_NATIVE;
    return 0;
  }
  return previous_xerror ? previous_xerror(display, e) : 0;
}
static void begin_xerror_scope(struct host *h) {
  if (!xerror_depth++) {
    error_host = h;
    previous_xerror = XSetErrorHandler(xerror);
  }
}
static void end_xerror_scope(struct host *h) {
  XSync(h->display, False);
  if (!--xerror_depth) {
    XSetErrorHandler(previous_xerror);
    error_host = NULL;
  }
}
static void finish_transfer(struct host *h, struct selection_transfer *t) {
  if (!t->requestor) return;
  int other = 0;
  for (int i = 0; i < TRANSFER_CAPACITY; ++i)
    if (&h->transfers[i] != t && h->transfers[i].requestor == t->requestor) other = 1;
  if (!other && h->display) {
    begin_xerror_scope(h);
    XSelectInput(h->display, t->requestor, t->previous_mask);
    end_xerror_scope(h);
  }
  free(t->bytes); memset(t, 0, sizeof(*t));
}
static void selection_request(struct host *h, XSelectionRequestEvent *r) {
  begin_xerror_scope(h);
  XEvent response = {0};
  response.xselection.type = SelectionNotify;
  response.xselection.display = h->display;
  response.xselection.requestor = r->requestor;
  response.xselection.selection = r->selection;
  response.xselection.target = r->target;
  response.xselection.time = r->time;
  response.xselection.property = None;
  Atom property = r->property ? r->property : r->target;
  if (r->selection == h->clipboard && h->owns_clipboard) {
    if (r->target == h->targets) {
      Atom targets[] = {h->targets, h->utf8};
      XChangeProperty(h->display, r->requestor, property, XA_ATOM, 32,
          PropModeReplace, (unsigned char *)targets, 2);
      response.xselection.property = property;
    } else if (r->target == h->utf8) {
      if (h->clipboard_owned_length <= CLIPBOARD_CHUNK) {
        XChangeProperty(h->display, r->requestor, property, h->utf8, 8,
            PropModeReplace, h->clipboard_owned, (int)h->clipboard_owned_length);
        response.xselection.property = property;
      } else {
        struct selection_transfer *t = NULL;
        int duplicate = 0;
        for (int i = 0; i < TRANSFER_CAPACITY; ++i)
          if (h->transfers[i].requestor == r->requestor && h->transfers[i].property == property)
            duplicate = 1;
        if (!duplicate)
          for (int i = 0; i < TRANSFER_CAPACITY; ++i)
            if (!h->transfers[i].requestor) { t = &h->transfers[i]; break; }
        if (t) {
          XWindowAttributes attrs;
          if (XGetWindowAttributes(h->display, r->requestor, &attrs)) {
            t->bytes = malloc(h->clipboard_owned_length);
            if (t->bytes) {
              memcpy(t->bytes, h->clipboard_owned, h->clipboard_owned_length);
              t->requestor = r->requestor; t->property = property;
              t->length = h->clipboard_owned_length; t->previous_mask = attrs.your_event_mask;
              for (int i = 0; i < TRANSFER_CAPACITY; ++i)
                if (&h->transfers[i] != t && h->transfers[i].requestor == r->requestor)
                  t->previous_mask = h->transfers[i].previous_mask;
              t->deadline = monotonic_milliseconds() + CLIPBOARD_TIMEOUT_MS;
              XSelectInput(h->display, r->requestor, attrs.your_event_mask | PropertyChangeMask);
              unsigned long length = t->length;
              XChangeProperty(h->display, r->requestor, property, h->incr, 32,
                  PropModeReplace, (unsigned char *)&length, 1);
              response.xselection.property = property;
            }
          }
        }
      }
    }
  }
  XSendEvent(h->display, r->requestor, False, 0, &response);
  end_xerror_scope(h);
}
static void selection_failed(struct host *h, int status) {
  h->selection_status = status; h->selection_done = 1;
  if (h->selection_window) {
    begin_xerror_scope(h);
    XDeleteProperty(h->display, h->selection_window, h->selection_property);
    end_xerror_scope(h);
  }
}
static void read_selection_property(struct host *h, int initial) {
  Atom type = None; int format = 0;
  unsigned long count = 0, after = 0;
  unsigned char *bytes = NULL;
  begin_xerror_scope(h);
  int s = XGetWindowProperty(h->display, h->selection_window, h->selection_property,
      0, CLIPBOARD_LIMIT / 4 + 1, True, AnyPropertyType, &type, &format, &count, &after, &bytes);
  end_xerror_scope(h);
  if (s != Success || after) {
    XFree(bytes); selection_failed(h, after ? GPUI_RESOURCE : GPUI_NATIVE); return;
  }
  if (initial && type == h->incr) {
    if (format != 32 || count != 1 || !bytes || *(unsigned long *)bytes > CLIPBOARD_LIMIT) {
      XFree(bytes); selection_failed(h, GPUI_RESOURCE); return;
    }
    h->selection_incr = 1; XFree(bytes); XFlush(h->display); return;
  }
  if (format != 8 || type != h->selection_target || count > CLIPBOARD_LIMIT - h->clipboard_result_length) {
    XFree(bytes); selection_failed(h, count > CLIPBOARD_LIMIT - h->clipboard_result_length ? GPUI_RESOURCE : GPUI_UNSUPPORTED); return;
  }
  if (count) {
    uint8_t *result = realloc(h->clipboard_result, h->clipboard_result_length + count);
    if (!result) { XFree(bytes); selection_failed(h, GPUI_RESOURCE); return; }
    h->clipboard_result = result;
    memcpy(result + h->clipboard_result_length, bytes, count);
    h->clipboard_result_length += count;
  }
  XFree(bytes);
  if (!h->selection_incr || !count) h->selection_done = 1;
  XFlush(h->display);
}
static void property_event(struct host *h, XPropertyEvent *e) {
  if (h->selection_wait && h->selection_incr && !h->selection_done &&
      e->window == h->selection_window && e->atom == h->selection_property && e->state == PropertyNewValue)
    read_selection_property(h, 0);
  if (e->state != PropertyDelete) return;
  for (int i = 0; i < TRANSFER_CAPACITY; ++i) {
    struct selection_transfer *t = &h->transfers[i];
    if (t->requestor != e->window || t->property != e->atom) continue;
    begin_xerror_scope(h);
    size_t n = t->length - t->offset;
    if (n > CLIPBOARD_CHUNK) n = CLIPBOARD_CHUNK;
    XChangeProperty(h->display, t->requestor, t->property, h->utf8, 8,
        PropModeReplace, t->bytes + t->offset, (int)n);
    t->offset += n;
    t->deadline = monotonic_milliseconds() + CLIPBOARD_TIMEOUT_MS;
    if (!n) finish_transfer(h, t);
    end_xerror_scope(h);
  }
}
static void handle_event(struct host *h, XEvent *e) {
  if (e->type == MappingNotify) {
    XRefreshKeyboardMapping(&e->xmapping);
    /* MappingNotify has no target window. Fence queued old-map input but keep
     * a focused editor armed; no focus transition exists for it to rearm on. */
    if (advance_direct_epoch(h)) h->error = GPUI_RESOURCE;
    /* Keep held-key epochs so their old-map repeat/release is suppressed. */
    return;
  }
  if (e->type == SelectionRequest) { selection_request(h, &e->xselectionrequest); return; }
  if (e->type == PropertyNotify) { property_event(h, &e->xproperty); return; }
  if (e->type == SelectionClear && e->xselectionclear.selection == h->clipboard) {
    /* An older SelectionClear may be queued behind a fresh copy/reacquire. */
    h->owns_clipboard = h->xwindow && XGetSelectionOwner(h->display, h->clipboard) == h->xwindow;
    return;
  }
  if (e->type == SelectionNotify && h->selection_wait && !h->selection_done &&
      e->xselection.requestor == h->selection_window && e->xselection.selection == h->clipboard &&
      e->xselection.target == h->selection_target) {
    if (e->xselection.property == h->selection_property) read_selection_property(h, 1);
    else selection_failed(h, GPUI_UNSUPPORTED);
    return;
  }
  if (!h->xwindow || e->xany.window != h->xwindow) return;
  switch (e->type) {
    case ConfigureNotify:
      if (valid_size(e->xconfigure.width, e->xconfigure.height, 1) &&
          (h->width != e->xconfigure.width || h->height != e->xconfigure.height)) {
        h->width = e->xconfigure.width; h->height = e->xconfigure.height;
        event(h, 1, 0, 0, 0);
      }
      break;
    case ClientMessage:
      if (e->xclient.message_type == h->wm_protocols && e->xclient.format == 32 &&
          (Atom)e->xclient.data.l[0] == h->wm_delete) {
        reset_direct_text(h); event(h, 3, 0, 0, 0);
      }
      break;
    case FocusIn: case FocusOut:
      if (e->xfocus.mode == NotifyGrab || e->xfocus.mode == NotifyUngrab || e->xfocus.detail == NotifyInferior) break;
      if (h->keyboard_focus_current != (e->type == FocusIn)) {
        reset_direct_text(h); h->keyboard_focus_current = e->type == FocusIn;
        event(h, 6, h->keyboard_focus_current, 0, 0);
      }
      break;
    case KeyPress: keyboard_key(h, &e->xkey, 1); break;
    case KeyRelease:
      /* Non-detectable servers synthesize release/press pairs for repeat. */
      if (!h->detectable_repeat && XPending(h->display)) {
        XEvent next; XPeekEvent(h->display, &next);
        if (next.type == KeyPress && next.xkey.window == e->xkey.window &&
            next.xkey.keycode == e->xkey.keycode && next.xkey.time == e->xkey.time) break;
      }
      keyboard_key(h, &e->xkey, 0); break;
    case EnterNotify: case MotionNotify:
      h->px = e->type == MotionNotify ? e->xmotion.x : e->xcrossing.x;
      h->py = e->type == MotionNotify ? e->xmotion.y : e->xcrossing.y;
      h->modifiers = modifiers(e->type == MotionNotify ? e->xmotion.state : e->xcrossing.state);
      event(h, 7, 0, h->px, h->py); break;
    case ButtonPress: case ButtonRelease: {
      unsigned button = e->xbutton.button;
      h->px = e->xbutton.x; h->py = e->xbutton.y; h->modifiers = modifiers(e->xbutton.state);
      if (button >= 4 && button <= 7) {
        if (e->type == ButtonPress) {
          int slot = (h->read + h->count) % QUEUE_CAPACITY, prior = h->count;
          event(h, 10, button >= 6, h->px, h->py);
          if (prior != h->count) h->queue[slot][4] = button == 4 || button == 6 ? -40 : 40;
        }
      } else if (button == 1 || button == 2 || button == 3 || button == 8 || button == 9) {
        int detail = button == 1 ? 0 : button == 3 ? 1 : button == 2 ? 2 : button == 8 ? 3 : 4;
        event(h, e->type == ButtonPress ? 8 : 9, detail, h->px, h->py);
      }
      break;
    }
    case Expose:
      if (!e->xexpose.count) event(h, 1, 0, 0, 0);
      break;
    case DestroyNotify:
      reset_direct_text(h); event(h, 4, 0, 0, 0);
      h->xwindow = 0; h->state = 1; release_window(h); break;
    default: break;
  }
}
/* Synchronous clipboard reads service selection traffic while leaving input
 * in Xlib order for the application to consume after its clipboard call. */
static Bool selection_predicate(Display *display, XEvent *e, XPointer data) {
  UNUSED(display);
  struct host *h = (struct host *)data;
  return e->type == SelectionRequest || e->type == SelectionNotify ||
      e->type == SelectionClear || e->type == PropertyNotify ||
      (e->type == DestroyNotify && e->xdestroywindow.window == h->xwindow);
}
static int drain_native(struct host *h) {
  int handled = 0;
  for (int i = 0; i < 512 && !h->error; ++i) {
    XEvent e;
    if (h->selection_wait) {
      if (!XCheckIfEvent(h->display, &e, selection_predicate, (XPointer)h)) break;
    } else {
      if (h->count || !XPending(h->display)) break;
      XNextEvent(h->display, &e);
    }
    handle_event(h, &e);
    handled = 1;
    if (h->state || (h->selection_wait && h->selection_done)) break;
  }
  return handled;
}
static int pump(struct host *h, int timeout) {
  if (h->error) return h->error;
  if (h->count && !h->selection_wait) return GPUI_OK;
  XFlush(h->display);
  int handled = drain_native(h);
  if (!handled && !h->state && !h->error && timeout > 0) {
    struct pollfd fds[2] = {{ConnectionNumber(h->display), POLLIN, 0}, {h->wake_fd, POLLIN, 0}};
    int r = poll(fds, 2, timeout);
    /* EINTR yields immediately; it must never restart the full timeout. */
    if (r < 0 && errno == EINTR) return GPUI_OK;
    if (r < 0 || (fds[0].revents & (POLLERR | POLLHUP | POLLNVAL))) {
      reset_direct_text(h); h->state = 1; return h->error = GPUI_NATIVE;
    }
    if (fds[1].revents & POLLIN) { uint64_t value; UNUSED(read(h->wake_fd, &value, sizeof(value))); }
    if (fds[0].revents & POLLIN) (void)drain_native(h);
  }
  int64_t now = monotonic_milliseconds();
  for (int i = 0; i < TRANSFER_CAPACITY; ++i)
    if (h->transfers[i].requestor && (now < 0 || now >= h->transfers[i].deadline)) finish_transfer(h, &h->transfers[i]);
  return h->error;
}

#include "../platform/linux_renderer/programs.inc.c"
static void release_renderer(struct host *h, int terminate) {
  if (h->egl != EGL_NO_DISPLAY) {
    eglMakeCurrent(h->egl, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    if (h->egl_surface != EGL_NO_SURFACE) eglDestroySurface(h->egl, h->egl_surface);
    if (h->context != EGL_NO_CONTEXT) eglDestroyContext(h->egl, h->context);
    if (terminate) eglTerminate(h->egl);
  }
  h->egl_surface = EGL_NO_SURFACE; h->context = EGL_NO_CONTEXT;
  h->program = h->mask_program = 0;
  if (terminate) { h->egl = EGL_NO_DISPLAY; h->config = NULL; }
}
static int prepare_gpu(struct host *h) {
  if (h->egl != EGL_NO_DISPLAY) return GPUI_OK;
  PFNEGLGETPLATFORMDISPLAYEXTPROC get_display =
      (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
  h->egl = get_display ? get_display(EGL_PLATFORM_X11_EXT, h->display, NULL) :
      eglGetDisplay((EGLNativeDisplayType)h->display);
  if (h->egl == EGL_NO_DISPLAY || !eglInitialize(h->egl, NULL, NULL) || !eglBindAPI(EGL_OPENGL_ES_API)) {
    release_renderer(h, 1); return GPUI_DEVICE_LOST;
  }
  const EGLint attrs[] = {EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE,
      EGL_OPENGL_ES2_BIT, EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8,
      EGL_ALPHA_SIZE, 8, EGL_NONE};
  EGLint n;
  if (!eglChooseConfig(h->egl, attrs, &h->config, 1, &n) || !n) {
    release_renderer(h, 1); return GPUI_DEVICE_LOST;
  }
  return GPUI_OK;
}
static int create_gpu(struct host *h) {
  int s = prepare_gpu(h);
  if (s) return s;
  const EGLint attrs[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
  h->context = eglCreateContext(h->egl, h->config, EGL_NO_CONTEXT, attrs);
  if (h->context == EGL_NO_CONTEXT) return GPUI_DEVICE_LOST;
  h->egl_surface = eglCreateWindowSurface(h->egl, h->config, (EGLNativeWindowType)h->xwindow, NULL);
  if (h->egl_surface == EGL_NO_SURFACE || !eglMakeCurrent(h->egl, h->egl_surface, h->egl_surface, h->context))
    return GPUI_SURFACE_LOST;
  /* Swap completion means renderer readiness, not a compositor timestamp. */
  eglSwapInterval(h->egl, 1);
  return create_programs(h);
}
static void release_window(struct host *h) {
  reset_direct_text(h);
  release_renderer(h, 0);
  for (int i = 0; i < TRANSFER_CAPACITY; ++i) finish_transfer(h, &h->transfers[i]);
  if (h->display) {
    begin_xerror_scope(h);
    if (h->selection_window) XDestroyWindow(h->display, h->selection_window);
    h->selection_window = 0;
    if (h->xwindow) XDestroyWindow(h->display, h->xwindow);
    if (h->colormap) XFreeColormap(h->display, h->colormap);
    end_xerror_scope(h);
  }
  h->xwindow = 0; h->colormap = 0; h->window = 0; h->configured = 0;
  h->keyboard_focus_current = 0; h->owns_clipboard = 0;
  free(h->frame_pixels); h->frame_pixels = NULL;
  h->frame_width = h->frame_height = h->frame_scale = 0;
}
static void release_host(struct host *h) {
  release_window(h); release_renderer(h, 1);
  if (h->compose) xkb_compose_state_unref(h->compose);
  if (h->compose_table) xkb_compose_table_unref(h->compose_table);
  if (h->xkb) xkb_context_unref(h->xkb);
  if (h->display) {
    for (int i = 0; i < 3; ++i) if (h->cursors[i]) XFreeCursor(h->display, h->cursors[i]);
    XSync(h->display, False);
    XCloseDisplay(h->display);
  }
  if (h->wake_fd >= 0) close(h->wake_fd);
  free(h->clipboard_owned); free(h->clipboard_result); free(h);
}
int32_t gpui_x11_start(int32_t abi) {
  if (abi != GPUI_X11_ABI) return -GPUI_INVALID;
  pthread_mutex_lock(&registry_mutex);
  if (active || stopping) { pthread_mutex_unlock(&registry_mutex); return -GPUI_BUSY; }
  if (!getenv("DISPLAY") || !*getenv("DISPLAY")) { pthread_mutex_unlock(&registry_mutex); return -GPUI_UNSUPPORTED; }
  if (next_host == INT_MAX) { pthread_mutex_unlock(&registry_mutex); return -GPUI_RESOURCE; }
  struct host *h = calloc(1, sizeof(*h));
  if (!h) { pthread_mutex_unlock(&registry_mutex); return -GPUI_RESOURCE; }
  h->wake_fd = -1; h->owner = pthread_self(); h->scale = 1;
  h->egl = EGL_NO_DISPLAY; h->context = EGL_NO_CONTEXT; h->egl_surface = EGL_NO_SURFACE;
  h->display = XOpenDisplay(NULL);
  h->wake_fd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
  h->xkb = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
  if (!h->display || h->wake_fd < 0 || !h->xkb) {
    release_host(h); pthread_mutex_unlock(&registry_mutex); return -GPUI_NATIVE;
  }
  const char *locale = getenv("LC_ALL");
  if (!locale || !*locale) locale = getenv("LC_CTYPE");
  if (!locale || !*locale) locale = getenv("LANG");
  if (!locale || !*locale) locale = "C";
  h->compose_table = xkb_compose_table_new_from_locale(h->xkb, locale, XKB_COMPOSE_COMPILE_NO_FLAGS);
  if (h->compose_table) h->compose = xkb_compose_state_new(h->compose_table, XKB_COMPOSE_STATE_NO_FLAGS);
  Bool detectable = False;
  h->detectable_repeat = XkbSetDetectableAutoRepeat(h->display, True, &detectable) && detectable;
  h->wm_protocols = XInternAtom(h->display, "WM_PROTOCOLS", False);
  h->wm_delete = XInternAtom(h->display, "WM_DELETE_WINDOW", False);
  h->net_name = XInternAtom(h->display, "_NET_WM_NAME", False);
  h->utf8 = XInternAtom(h->display, "UTF8_STRING", False);
  h->clipboard = XInternAtom(h->display, "CLIPBOARD", False);
  h->targets = XInternAtom(h->display, "TARGETS", False);
  h->incr = XInternAtom(h->display, "INCR", False);
  h->selection_property = XInternAtom(h->display, "GPUI_X11_SELECTION", False);
  begin_xerror_scope(h);
  h->cursors[0] = XCreateFontCursor(h->display, XC_left_ptr);
  h->cursors[1] = XCreateFontCursor(h->display, XC_hand2);
  h->cursors[2] = XCreateFontCursor(h->display, XC_xterm);
  end_xerror_scope(h);
  if (h->error) {
    release_host(h); pthread_mutex_unlock(&registry_mutex); return -GPUI_NATIVE;
  }
  h->token = next_host++; active = h;
  pthread_mutex_unlock(&registry_mutex);
  return h->token;
}
int32_t gpui_x11_state(int32_t token) { struct host *h; return check(token, &h) ? 2 : h->state; }
int32_t gpui_x11_stop(int32_t token) {
  struct host *h; int s = check(token, &h);
  if (s == GPUI_STALE) return GPUI_OK;
  if (s) return s;
  h->state = 1;
  pthread_mutex_lock(&registry_mutex);
  active = NULL;
  stopping = 1;
  pthread_mutex_unlock(&registry_mutex);
  release_host(h);
  pthread_mutex_lock(&registry_mutex);
  stopping = 0;
  pthread_mutex_unlock(&registry_mutex);
  return GPUI_OK;
}
int32_t gpui_x11_wake(int32_t token) {
  struct host *h; int s = check(token, &h); if (s) return s;
  uint64_t value = 1;
  return write(h->wake_fd, &value, sizeof(value)) < 0 && errno != EAGAIN ? GPUI_NATIVE : GPUI_OK;
}
int32_t gpui_x11_exit(int32_t token) {
  struct host *h; int s = check(token, &h); if (s) return s;
  reset_direct_text(h); h->state = 1;
  return gpui_x11_wake(token);
}
static int title_valid(const uint8_t *title, int length) {
  return length >= 0 && length <= 4096 && (title || !length) &&
      !(length && memchr(title, 0, (size_t)length)) && direct_utf8_valid(title, length);
}
static void set_title(struct host *h, const uint8_t *title, int length) {
  XChangeProperty(h->display, h->xwindow, h->net_name, h->utf8, 8, PropModeReplace, title, length);
  XChangeProperty(h->display, h->xwindow, XA_WM_NAME, h->utf8, 8, PropModeReplace, title, length);
}
int32_t gpui_x11_create(int32_t token, int32_t w, int32_t hh, const uint8_t *title, int32_t length) {
  struct host *h; int s = check(token, &h); if (s) return -s;
  if (h->state) return -GPUI_STOPPING;
  if (h->window) return -GPUI_BUSY;
  if (!valid_size(w, hh, 1) || !title_valid(title, length)) return -GPUI_INVALID;
  if (next_window == INT_MAX) return -GPUI_RESOURCE;
  s = prepare_gpu(h); if (s) return -s;
  EGLint visual_id;
  if (!eglGetConfigAttrib(h->egl, h->config, EGL_NATIVE_VISUAL_ID, &visual_id)) return -GPUI_DEVICE_LOST;
  XVisualInfo template = {.visualid = (VisualID)visual_id}; int n = 0;
  XVisualInfo *visual = XGetVisualInfo(h->display, VisualIDMask, &template, &n);
  if (!visual || !n) { XFree(visual); return -GPUI_UNSUPPORTED; }
  Window root = RootWindow(h->display, visual->screen);
  begin_xerror_scope(h);
  h->colormap = XCreateColormap(h->display, root, visual->visual, AllocNone);
  XSetWindowAttributes attrs = {0};
  attrs.colormap = h->colormap; attrs.border_pixel = 0;
  attrs.event_mask = StructureNotifyMask | ExposureMask | FocusChangeMask | PointerMotionMask |
      EnterWindowMask | LeaveWindowMask | ButtonPressMask | ButtonReleaseMask |
      KeyPressMask | KeyReleaseMask | PropertyChangeMask;
  h->xwindow = XCreateWindow(h->display, root, 0, 0, (unsigned)w, (unsigned)hh, 0,
      visual->depth, InputOutput, visual->visual, CWColormap | CWBorderPixel | CWEventMask, &attrs);
  XFree(visual);
  if (!h->xwindow) { end_xerror_scope(h); release_window(h); return -GPUI_NATIVE; }
  h->width = w; h->height = hh; h->scale = 1;
  XSetWMProtocols(h->display, h->xwindow, &h->wm_delete, 1);
  XClassHint class_hint = {.res_name = "gpui", .res_class = "gpui.mbt"};
  XSetClassHint(h->display, h->xwindow, &class_hint);
  unsigned long pid = (unsigned long)getpid();
  XChangeProperty(h->display, h->xwindow, XInternAtom(h->display, "_NET_WM_PID", False),
      XA_CARDINAL, 32, PropModeReplace, (unsigned char *)&pid, 1);
  set_title(h, title, length);
  XDefineCursor(h->display, h->xwindow, h->cursors[h->cursor_kind]);
  XMapWindow(h->display, h->xwindow); end_xerror_scope(h);
  s = h->error ? h->error : create_gpu(h);
  if (s) { release_window(h); return -s; }
  h->window = next_window++; h->configured = 1;
  event(h, 1, 0, 0, 0);
  if (native_e2e_enabled()) {
    fprintf(stderr, "GPUI_X11_WINDOW {\"pid\":%ld,\"window\":%lu,\"width\":%d,\"height\":%d}\n", (long)getpid(), h->xwindow, w, hh);
    fflush(stderr);
  }
  return h->window;
}
int32_t gpui_x11_close(int32_t token, int32_t window) {
  struct host *h; int s = window_check(token, window, &h); if (s) return s;
  reset_direct_text(h); event(h, 3, 0, 0, 0); return h->error;
}
int32_t gpui_x11_destroy(int32_t token, int32_t window) {
  struct host *h; int s = check(token, &h); if (s) return s;
  if (window > 0 && window < next_window && h->window != window) return GPUI_OK;
  if (!window || h->window != window) return GPUI_STALE;
  h->read = h->count = 0;
  event(h, 4, 0, 0, 0); release_window(h); XFlush(h->display); return h->error;
}
int32_t gpui_x11_title(int32_t token, int32_t window, const uint8_t *title, int32_t length) {
  struct host *h; int s = window_check(token, window, &h); if (s) return s;
  if (!title_valid(title, length)) return GPUI_INVALID;
  begin_xerror_scope(h);
  set_title(h, title, length);
  end_xerror_scope(h);
  return h->error;
}
int32_t gpui_x11_size(int32_t token, int32_t window, int32_t w, int32_t hh) {
  struct host *h; int s = window_check(token, window, &h); if (s) return s;
  if (!valid_size(w, hh, 1)) return GPUI_INVALID;
  begin_xerror_scope(h);
  XResizeWindow(h->display, h->xwindow, (unsigned)w, (unsigned)hh);
  end_xerror_scope(h);
  /* ConfigureNotify commits the server's accepted size; no speculative metrics. */
  return h->error;
}
int32_t gpui_x11_metrics(int32_t token, int32_t window, double *out) {
  struct host *h; int s = window_check(token, window, &h); if (s) return s;
  if (!out) return GPUI_INVALID;
  out[0] = h->width; out[1] = h->height; out[2] = h->scale; return GPUI_OK;
}
int32_t gpui_x11_dispatch(int32_t token, int32_t timeout) {
  struct host *h; int s = check(token, &h); if (s) return s;
  if (timeout < 0 || timeout > 60000) return GPUI_INVALID;
  return pump(h, h->count || h->state ? 0 : timeout);
}
static int stale_direct_record(const struct host *h, int slot) {
  double kind = h->queue[slot][0];
  if (kind != 11 && kind != 12 && kind != 13) return 0;
  const struct direct_event_meta *m = &h->direct_queue[slot];
  if (m->revoked || (m->direct_origin && (h->state || h->direct_exhausted))) return 1;
  if ((m->direct_origin || h->direct_enabled) && m->epoch != h->direct_epoch) return 1;
  return m->direct_origin && (!h->direct_enabled || !h->keyboard_focus_current);
}
static void consume_event(struct host *h) {
  memset(&h->direct_queue[h->read], 0, sizeof(h->direct_queue[h->read]));
  h->read = (h->read + 1) % QUEUE_CAPACITY; --h->count;
}
int32_t gpui_x11_next(int32_t token, double *out) {
  struct host *h; int s = check(token, &h); if (s) return -s;
  if (!out) return -GPUI_INVALID;
  if (h->direct_exhausted && h->direct_ever_enabled) return -GPUI_RESOURCE;
  if (h->direct_enabled) return -GPUI_UNSUPPORTED;
  for (int i = 0; i < h->count; ++i) {
    int slot = (h->read + i) % QUEUE_CAPACITY;
    if (h->queue[slot][0] == 13 || h->direct_queue[slot].direct_origin || h->direct_queue[slot].revoked)
      return -GPUI_UNSUPPORTED;
  }
  if (!h->count) return 0;
  memcpy(out, h->queue[h->read], sizeof(h->queue[0])); consume_event(h); return 1;
}
int32_t gpui_x11_next_v2(int32_t abi, int32_t token, double *out, int32_t capacity,
    uint8_t *text, int32_t text_capacity) {
  if (abi != GPUI_DIRECT_TEXT_ABI) return -GPUI_UNSUPPORTED;
  if (!out || capacity < 0 || text_capacity < 0 || (!text && text_capacity)) return -GPUI_INVALID;
  if (capacity < 10) return -GPUI_RESOURCE;
  struct host *h; int s = check(token, &h); if (s) return -s;
  if (h->direct_exhausted && h->direct_ever_enabled) return -GPUI_RESOURCE;
  int skipped = 0;
  while (skipped < h->count && stale_direct_record(h, (h->read + skipped) % QUEUE_CAPACITY)) ++skipped;
  if (skipped == h->count) { while (h->count) consume_event(h); return 0; }
  int slot = (h->read + skipped) % QUEUE_CAPACITY;
  const struct direct_event_meta *m = &h->direct_queue[slot];
  if (h->queue[slot][0] == 13) {
    if (m->text_length <= 0 || m->text_length > GPUI_DIRECT_TEXT_MAX_BYTES ||
        h->queue[slot][8] != m->text_length || !direct_utf8_valid(m->text, m->text_length)) return -GPUI_INVALID;
    if (text_capacity < m->text_length) return -GPUI_RESOURCE;
  }
  memcpy(out, h->queue[slot], sizeof(h->queue[slot]));
  if (h->queue[slot][0] == 13) memcpy(text, m->text, (size_t)m->text_length);
  for (int i = 0; i <= skipped; ++i) consume_event(h);
  return 1;
}
int32_t gpui_x11_direct_keyboard_text_mode(int32_t token, int32_t window, int32_t enabled) {
  struct host *h; int s = window_check(token, window, &h); if (s) return s;
  if (enabled != 0 && enabled != 1) return GPUI_INVALID;
  if (h->direct_exhausted) return GPUI_RESOURCE;
  if (enabled) {
    s = require_direct_keyboard(h); if (s) return s;
    if (!h->keyboard_focus_current) return GPUI_UNSUPPORTED;
  }
  s = advance_direct_epoch(h); if (s) return s;
  h->direct_enabled = enabled;
  if (enabled) h->direct_ever_enabled = 1;
  return GPUI_OK;
}
int32_t gpui_x11_direct_keyboard_text_epoch(int32_t token, int32_t window) {
  struct host *h; int s = window_check(token, window, &h); if (s) return -s;
  if (h->direct_exhausted) return -GPUI_RESOURCE;
  if (h->state) return -GPUI_STOPPING;
  return h->direct_enabled && h->keyboard_focus_current ? h->direct_epoch : -GPUI_UNSUPPORTED;
}
int32_t gpui_x11_direct_keyboard_text_active(int32_t token) {
  struct host *h; int s = check(token, &h); return s ? -s : !h->state && h->direct_enabled;
}
static int submit_frame(struct host *h) {
  if (h->count == QUEUE_CAPACITY || h->seq == INT_MAX) return GPUI_RESOURCE;
  if (!eglSwapBuffers(h->egl, h->egl_surface))
    return eglGetError() == EGL_CONTEXT_LOST ? GPUI_DEVICE_LOST : GPUI_SURFACE_LOST;
  event(h, 5, 0, 0, 0);
  if (native_e2e_enabled()) {
    fprintf(stderr, "GPUI_X11_FRAME {\"window\":%lu,\"width\":%d,\"height\":%d}\n", h->xwindow, h->width, h->height);
    fflush(stderr);
  }
  return h->error;
}
#define GPUI_RENDER_EXPORT(name) gpui_x11_##name
#include "../platform/linux_renderer/frame.inc.c"
#undef GPUI_RENDER_EXPORT
int32_t gpui_x11_recover(int32_t token, int32_t window) {
  struct host *h; int s = window_check(token, window, &h); if (s) return s;
  if (h->state) return GPUI_STOPPING;
  release_renderer(h, 0); s = create_gpu(h);
  if (s) release_renderer(h, 0);
  return s;
}
int32_t gpui_x11_capability(int32_t token, int32_t capability) {
  struct host *h; int s = check(token, &h); if (s) return s;
  if (capability == 1) return GPUI_OK;
  if (capability == 2) return h->cursors[0] && h->cursors[1] && h->cursors[2] ? GPUI_OK : GPUI_UNSUPPORTED;
  if (capability == 3) return require_direct_keyboard(h);
  return GPUI_UNSUPPORTED;
}
int32_t gpui_x11_write_clipboard(int32_t token, const uint8_t *bytes, int32_t length) {
  struct host *h; int s = check(token, &h); if (s) return s;
  if (h->state) return GPUI_STOPPING;
  if (!h->window) return GPUI_STALE;
  if (length < 0 || (!bytes && length)) return GPUI_INVALID;
  if (length > CLIPBOARD_LIMIT) return GPUI_RESOURCE;
  if ((length && memchr(bytes, 0, (size_t)length)) || !direct_utf8_valid(bytes, length)) return GPUI_INVALID;
  uint8_t *copy = malloc(length ? (size_t)length : 1);
  if (!copy) return GPUI_RESOURCE;
  if (length) memcpy(copy, bytes, (size_t)length);
  begin_xerror_scope(h);
  XSetSelectionOwner(h->display, h->clipboard, h->xwindow, CurrentTime);
  Window owner = XGetSelectionOwner(h->display, h->clipboard);
  end_xerror_scope(h);
  if (h->error || owner != h->xwindow) { free(copy); return h->error ? h->error : GPUI_NATIVE; }
  free(h->clipboard_owned); h->clipboard_owned = copy; h->clipboard_owned_length = (size_t)length;
  h->owns_clipboard = 1; XFlush(h->display); return GPUI_OK;
}
int32_t gpui_x11_read_clipboard(int32_t token) {
  struct host *h; int s = check(token, &h); if (s) return s;
  if (h->state) return GPUI_STOPPING;
  if (!h->window) return GPUI_STALE;
  if (h->selection_wait) return GPUI_BUSY;
  free(h->clipboard_result); h->clipboard_result = NULL; h->clipboard_result_length = 0;
  Window owner = XGetSelectionOwner(h->display, h->clipboard);
  if (owner == None) return GPUI_OK;
  if (owner == h->xwindow) {
    h->clipboard_result = malloc(h->clipboard_owned_length ? h->clipboard_owned_length : 1);
    if (!h->clipboard_result) return GPUI_RESOURCE;
    if (h->clipboard_owned_length) memcpy(h->clipboard_result, h->clipboard_owned, h->clipboard_owned_length);
    h->clipboard_result_length = h->clipboard_owned_length; return GPUI_OK;
  }
  h->selection_wait = 1; h->selection_done = h->selection_incr = h->selection_status = 0;
  h->selection_target = h->utf8;
  /* A new unmapped requestor gives every read a native identity. Destroying it
   * cancels a timed-out INCR stream, so late replies cannot satisfy a retry.
   * No unbounded per-read server atoms or retained helper windows are used. */
  XSetWindowAttributes attrs = {.event_mask = PropertyChangeMask};
  begin_xerror_scope(h);
  h->selection_window = XCreateWindow(h->display, DefaultRootWindow(h->display),
      0, 0, 1, 1, 0, 0, InputOnly, CopyFromParent, CWEventMask, &attrs);
  end_xerror_scope(h);
  if (!h->selection_window || h->error) {
    h->selection_wait = 0;
    return h->error ? h->error : GPUI_RESOURCE;
  }
  begin_xerror_scope(h);
  XConvertSelection(h->display, h->clipboard, h->utf8, h->selection_property, h->selection_window, CurrentTime);
  end_xerror_scope(h);
  s = h->error;
  int64_t now = monotonic_milliseconds();
  int64_t deadline = now >= 0 && now <= INT64_MAX - CLIPBOARD_TIMEOUT_MS ? now + CLIPBOARD_TIMEOUT_MS : -1;
  if (deadline < 0) s = GPUI_NATIVE;
  while (!h->selection_done && !s) {
    now = monotonic_milliseconds();
    if (now < 0) { s = GPUI_NATIVE; break; }
    int64_t left = deadline - now;
    if (left <= 0) { s = GPUI_NATIVE; break; }
    s = pump(h, left > 100 ? 100 : (int)left);
    if (!s && (h->state || !h->xwindow)) s = GPUI_STOPPING;
  }
  h->selection_wait = 0;
  if (h->selection_window) {
    begin_xerror_scope(h);
    XDestroyWindow(h->display, h->selection_window);
    h->selection_window = 0;
    end_xerror_scope(h);
  }
  if (!s) s = h->selection_status;
  if (!s && !direct_utf8_valid(h->clipboard_result, (int)h->clipboard_result_length)) s = GPUI_INVALID;
  if (s) { free(h->clipboard_result); h->clipboard_result = NULL; h->clipboard_result_length = 0; }
  return s;
}
int32_t gpui_x11_clipboard_length(int32_t token) {
  struct host *h; int s = check(token, &h); return s ? -s : (int32_t)h->clipboard_result_length;
}
int32_t gpui_x11_clipboard_copy(int32_t token, uint8_t *bytes, int32_t capacity) {
  struct host *h; int s = check(token, &h); if (s) return s;
  if (capacity < 0 || (!bytes && capacity)) return GPUI_INVALID;
  if ((size_t)capacity < h->clipboard_result_length) return GPUI_RESOURCE;
  if (h->clipboard_result_length) memcpy(bytes, h->clipboard_result, h->clipboard_result_length);
  return GPUI_OK;
}
int32_t gpui_x11_set_cursor(int32_t token, int32_t cursor) {
  struct host *h; int s = check(token, &h); if (s) return s;
  if (cursor < 0 || cursor > 2) return GPUI_INVALID;
  if (!h->cursors[cursor]) return GPUI_UNSUPPORTED;
  h->cursor_kind = cursor;
  if (h->xwindow) {
    begin_xerror_scope(h);
    XDefineCursor(h->display, h->xwindow, h->cursors[cursor]);
    end_xerror_scope(h);
  }
  return h->error;
}
