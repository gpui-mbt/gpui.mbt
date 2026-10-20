#import <AppKit/AppKit.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include "abi.h"
#include "../macos_text/macos_text.h"

@interface GPWindow : NSObject <NSWindowDelegate>
@property NSWindow *window;
@property CAMetalLayer *surface;
@property int64_t token, sequence;
@property double scale;
@property BOOL closing;
@property BOOL ime_enabled;
@property NSRect ime_caret;
@property BOOL text_armed;
@property int64_t text_epoch, text_sequence;
@end
@interface GPView : NSView <NSTextInputClient>
@property(weak) GPWindow *owner;
@property BOOL marked;
@property NSRange marked_range;
@property NSRange marked_selection;
@property(strong) NSString *marked_text;
@property NSUInteger last_modifiers;
@property unsigned short last_key_code;
@property BOOL ime_in_keydown;
@property int ime_keydown_outcome; // 0 none, 1 committed, 2 cancelled
- (void)resetImeState;
@end
static NSMutableDictionary<NSNumber *, GPWindow *> *windows;
static NSMutableArray<NSDictionary *> *events;
static NSMutableArray<NSDictionary *> *text_events;
static NSDictionary *current;
static id<MTLDevice> device;
static id<MTLCommandQueue> queue;
static id<MTLRenderPipelineState> pipeline;
static id<MTLTexture> white_mask_texture;
static int64_t next_token, result_token, host_epoch, next_text_epoch;
static NSData *text_result;
static int state; // 0 uninitialized/stopped, 1 running, 2 quiescing
static BOOL overflow, text_overflow, background_host;
#ifdef GPUI_TESTING
static NSData *frame_pixels;
static NSUInteger frame_width, frame_height, frame_stride;
static int64_t frame_window_token;
static double frame_scale;
static double test_scale_override;
static NSPasteboard *test_clipboard;
#endif
static void append_event(GPWindow *w, int kind, double x, double y, int mods,
                         int code, int repeat, double width, double height) {
  if (w.closing && kind != 13) return;
  if (events.count >= 4096) { overflow = YES; return; }
  int64_t sequence = w ? ++w.sequence : 0;
  [events addObject:@{@"kind":@(kind), @"token":@(w ? w.token : 0), @"seq":@(sequence),
    @"scale":@(w ? w.scale : 1), @"x":@(x), @"y":@(y), @"mods":@(mods), @"code":@(code), @"repeat":@(repeat),
    @"width":@(width), @"height":@(height)}];
}
static void emit(GPWindow *w, int kind, double x, double y, int mods, int code, int repeat) {
  append_event(w, kind, x, y, mods, code, repeat,
      w ? w.window.contentView.bounds.size.width : 0,
      w ? w.window.contentView.bounds.size.height : 0);
}
static void emit_scroll(GPWindow *w, double x, double y, double delta_x,
                        double delta_y, int mods) {
  append_event(w, 16, x, y, mods, 0, 0, delta_x, delta_y);
}
/* Composition frames are bounded at the host boundary. AppKit ranges and
 * MoonBit strings are UTF-16; the MoonBit decoder repeats the validation. */
static void emit_composition(GPWindow *w, int code, NSString *text,
                             NSUInteger cursor) {
  if (!w || w.closing) return;
  if (!text) text = @"";
  NSUInteger limit = code == 2 ? 65536 : 16384;
  if (text.length > limit) {
    NSRange tail = [text rangeOfComposedCharacterSequenceAtIndex:limit - 1];
    text = [text substringToIndex:tail.location];
  }
  if (cursor == NSNotFound || cursor > text.length) cursor = text.length;
  NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
  /* An armed text-input session owns composition delivery. A start frame needs
   * no portable record because the session epoch already identifies it. */
  if (w.text_armed) {
    if (code == 0) return;
    if (text_events.count >= 4096) { text_overflow = YES; return; }
    int64_t sequence = ++w.text_sequence;
    [text_events addObject:@{@"kind":@(code), @"token":@(w.token),
      @"seq":@(sequence), @"epoch":@(w.text_epoch), @"cursor":@((double)cursor),
      @"text":data}];
    return;
  }
  if (events.count >= 4096) { overflow = YES; return; }
  int64_t sequence = ++w.sequence;
  [events addObject:@{@"kind":@(17), @"token":@(w.token), @"seq":@(sequence),
    @"scale":@(w.scale), @"x":@(0.0), @"y":@(0.0), @"mods":@(0),
    @"code":@(code), @"repeat":@(0), @"width":@((double)cursor),
    @"height":@(0.0), @"text":data}];
}
static void emit_key(GPWindow *w, int kind, int mods, int code, int repeat,
                     NSString *text) {
  NSUInteger before = events.count;
  emit(w, kind, 0, 0, mods, code, repeat);
  if (events.count > before) {
    NSMutableDictionary *event = [events.lastObject mutableCopy];
    event[@"text"] = [text dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    events[events.count-1] = event;
  }
}
static void resize_surface(GPWindow *w) {
  double scale = w.window.backingScaleFactor;
#ifdef GPUI_TESTING
  if (test_scale_override > 0) scale = test_scale_override;
#endif
  BOOL changed = scale != w.scale;
  w.scale = scale;
  w.surface.contentsScale = scale;
  NSSize size = w.window.contentView.bounds.size;
  w.surface.drawableSize = CGSizeMake(MAX(1, ceil(size.width * scale)), MAX(1, ceil(size.height * scale)));
  if (changed) emit(w, 4, 0, 0, 0, 0, 0);
}
@implementation GPWindow
- (BOOL)windowShouldClose:(NSWindow *)sender { (void)sender; emit(self, 12, 0, 0, 0, 0, 0); return NO; }
- (void)windowDidResize:(NSNotification *)note { (void)note; resize_surface(self); emit(self, 2, 0, 0, 0, 0, 0); }
- (void)windowDidMove:(NSNotification *)note { (void)note; resize_surface(self); emit(self, 3, self.window.frame.origin.x, self.window.frame.origin.y, 0, 0, 0); }
- (void)windowDidChangeBackingProperties:(NSNotification *)note { (void)note; resize_surface(self); }
- (void)windowDidBecomeKey:(NSNotification *)note { (void)note; emit(self, 5, 0, 0, 0, 0, 0); }
- (void)windowDidResignKey:(NSNotification *)note {
  (void)note;
  [(GPView *)self.window.contentView unmarkText];
  if (self.text_armed && text_events.count < 4096) {
    [text_events addObject:@{@"kind":@(5), @"token":@(self.token),
      @"seq":@(++self.text_sequence), @"epoch":@(self.text_epoch),
      @"cursor":@(0.0), @"text":[NSData data]}];
  }
  emit(self, 6, 0, 0, 0, 0, 0);
}
@end
static int modifiers(NSEvent *event) {
  NSUInteger f = event.modifierFlags;
  return ((f & NSEventModifierFlagShift) ? 1 : 0) | ((f & NSEventModifierFlagControl) ? 2 : 0) |
    ((f & NSEventModifierFlagOption) ? 4 : 0) | ((f & NSEventModifierFlagCommand) ? 8 : 0);
}
@implementation GPView
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { (void)event; return YES; }
- (void)updateTrackingAreas {
  for (NSTrackingArea *area in self.trackingAreas) [self removeTrackingArea:area];
  [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseMoved | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil]];
  [super updateTrackingAreas];
}
- (void)pointer:(NSEvent *)event kind:(int)kind {
  GPWindow *owner = self.owner;
  if (!owner || owner.closing) return;
  resize_surface(owner);
  NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
  emit(owner, kind, p.x, p.y, modifiers(event), (int)event.buttonNumber, 0);
}
- (void)mouseMoved:(NSEvent *)e { [self pointer:e kind:7]; }
- (void)mouseDragged:(NSEvent *)e { [self pointer:e kind:7]; }
- (void)rightMouseDragged:(NSEvent *)e { [self pointer:e kind:7]; }
- (void)otherMouseDragged:(NSEvent *)e { [self pointer:e kind:7]; }
- (void)mouseDown:(NSEvent *)e { [self pointer:e kind:8]; }
- (void)rightMouseDown:(NSEvent *)e { [self pointer:e kind:8]; }
- (void)otherMouseDown:(NSEvent *)e { [self pointer:e kind:8]; }
- (void)mouseUp:(NSEvent *)e { [self pointer:e kind:9]; }
- (void)rightMouseUp:(NSEvent *)e { [self pointer:e kind:9]; }
- (void)otherMouseUp:(NSEvent *)e { [self pointer:e kind:9]; }
- (void)scrollWheel:(NSEvent *)e {
  GPWindow *owner = self.owner;
  if (!owner || owner.closing) return;
  resize_surface(owner);
  NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
  emit_scroll(owner, p.x, p.y, e.scrollingDeltaX, e.scrollingDeltaY,
              modifiers(e));
}
- (void)keyDown:(NSEvent *)e {
  GPWindow *owner = self.owner;
  if (!owner || owner.closing) return;
  resize_surface(owner);
  /* Command chords remain application shortcuts. Everything else is offered
   * to AppKit so dead keys and input methods can compose. */
  if (owner.ime_enabled &&
      (e.modifierFlags & NSEventModifierFlagCommand) == 0) {
    self.last_modifiers = e.modifierFlags;
    self.last_key_code = e.keyCode;
    self.ime_in_keydown = YES;
    self.ime_keydown_outcome = 0;
    [self interpretKeyEvents:@[e]];
    self.ime_in_keydown = NO;
    self.ime_keydown_outcome = 0;
    return;
  }
  [self key:e kind:10];
}
- (void)keyUp:(NSEvent *)e { [self key:e kind:11]; }
- (void)key:(NSEvent *)e kind:(int)kind {
  GPWindow *owner = self.owner;
  if (!owner || owner.closing) return;
  resize_surface(owner);
  emit_key(owner, kind, modifiers(e), (int)e.keyCode, e.isARepeat,
           e.charactersIgnoringModifiers ?: @"");
}
- (void)resetImeState {
  self.marked = NO;
  self.marked_text = nil;
  self.marked_range = NSMakeRange(NSNotFound, 0);
  self.marked_selection = NSMakeRange(NSNotFound, 0);
}
- (BOOL)resignFirstResponder {
  [self unmarkText];
  return [super resignFirstResponder];
}
/* NSTextInputClient. The app owns the document; these callbacks only publish
 * an ordered composition transaction and never edit a document here. */
- (BOOL)hasMarkedText { return self.marked; }
- (NSRange)markedRange {
  return self.marked ? self.marked_range : NSMakeRange(NSNotFound, 0);
}
- (NSRange)selectedRange {
  return self.marked ? self.marked_selection : NSMakeRange(NSNotFound, 0);
}
- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText {
  return @[];
}
- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range
                                                actualRange:(NSRangePointer)actualRange {
  (void)range;
  if (actualRange) *actualRange = NSMakeRange(NSNotFound, 0);
  return nil;
}
- (NSUInteger)characterIndexForPoint:(NSPoint)point {
  (void)point;
  return NSNotFound;
}
- (NSRect)firstRectForCharacterRange:(NSRange)range
                         actualRange:(NSRangePointer)actualRange {
  (void)range;
  if (actualRange) {
    *actualRange = self.marked ? self.marked_range : NSMakeRange(NSNotFound, 0);
  }
  NSRect caret = self.owner ? self.owner.ime_caret : NSZeroRect;
  if (!isfinite(NSMinX(caret)) || !isfinite(NSMinY(caret)) ||
      !isfinite(NSWidth(caret)) || !isfinite(NSHeight(caret)) ||
      NSWidth(caret) <= 0 || NSHeight(caret) <= 0) {
    caret = NSMakeRect(0, 0, 1, 18);
  }
  NSRect in_window = [self convertRect:caret toView:nil];
  return self.window ? [self.window convertRectToScreen:in_window] : in_window;
}
- (void)setMarkedText:(id)string selectedRange:(NSRange)selectedRange
      replacementRange:(NSRange)replacementRange {
  (void)replacementRange;
  GPWindow *owner = self.owner;
  if (!owner || owner.closing || !owner.ime_enabled) return;
  NSString *text = [string isKindOfClass:NSString.class]
      ? string
      : ([string isKindOfClass:NSAttributedString.class]
          ? [(NSAttributedString *)string string] : nil);
  if (!text || text.length == 0) {
    [self unmarkText];
    return;
  }
  if (!self.marked) {
    self.marked = YES;
    emit_composition(owner, 0, @"", 0);
  }
  if (selectedRange.location == NSNotFound ||
      selectedRange.location > text.length) {
    selectedRange.location = text.length;
  }
  if (selectedRange.length > text.length - selectedRange.location) {
    selectedRange.length = text.length - selectedRange.location;
  }
  self.marked_text = text;
  self.marked_range = NSMakeRange(0, text.length);
  self.marked_selection = selectedRange;
  emit_composition(owner, 1, text, selectedRange.location);
}
- (void)unmarkText {
  GPWindow *owner = self.owner;
  BOOL had_marked = self.marked;
  [self resetImeState];
  if (had_marked && owner && !owner.closing && owner.ime_enabled) {
    if (self.ime_in_keydown) self.ime_keydown_outcome = 2;
    emit_composition(owner, 3, @"", 0);
  }
}
- (void)insertText:(id)string replacementRange:(NSRange)replacementRange {
  (void)replacementRange;
  GPWindow *owner = self.owner;
  if (!owner || owner.closing || !owner.ime_enabled) return;
  NSString *text = [string isKindOfClass:NSString.class]
      ? string
      : ([string isKindOfClass:NSAttributedString.class]
          ? [(NSAttributedString *)string string] : nil);
  if (!text) return;
  if (self.ime_in_keydown) self.ime_keydown_outcome = 1;
  [self resetImeState];
  emit_composition(owner, 2, text, 0);
}
- (void)doCommandBySelector:(SEL)selector {
  int code = -1;
  NSUInteger mods = self.last_modifiers;
  if (selector == @selector(insertNewline:) ||
      selector == @selector(insertNewlineIgnoringFieldEditor:)) {
    code = 36;
  } else if (selector == @selector(cancelOperation:)) {
    code = 53;
  } else if (selector == @selector(deleteBackward:)) {
    code = 51;
  } else if (selector == @selector(deleteForward:)) {
    code = 117;
  } else if (selector == @selector(moveLeft:)) {
    code = 123;
  } else if (selector == @selector(moveRight:)) {
    code = 124;
  } else if (selector == @selector(moveDown:)) {
    code = 125;
  } else if (selector == @selector(moveUp:)) {
    code = 126;
  } else if (selector == @selector(moveToBeginningOfLine:) ||
             selector == @selector(moveToBeginningOfDocument:)) {
    code = 115;
  } else if (selector == @selector(moveToEndOfLine:) ||
             selector == @selector(moveToEndOfDocument:)) {
    code = 119;
  } else if (selector == @selector(scrollPageUp:)) {
    code = 116;
  } else if (selector == @selector(scrollPageDown:)) {
    code = 121;
  } else if (selector == @selector(insertTab:)) {
    code = 48;
  } else if (selector == @selector(insertBacktab:)) {
    code = 48;
    mods |= NSEventModifierFlagShift;
  }
  GPWindow *owner = self.owner;
  if (code < 0 || !owner || owner.closing) return;
  /* A synthetic or fallback key path may deliver Enter/Escape as commands
   * without the input method committing first. Resolve marked text here too. */
  if (code == 36 && self.marked) {
    [self insertText:self.marked_text replacementRange:self.marked_range];
    return;
  }
  if (code == 53 && self.marked) {
    [self unmarkText];
    return;
  }
  /* Enter commits and Escape cancels inside the IME. Do not forward the same
   * key as an application command after that terminal callback. */
  if (code == 36 && self.ime_keydown_outcome == 1) {
    self.ime_keydown_outcome = 0;
    return;
  }
  if (code == 53 && self.ime_keydown_outcome == 2) {
    self.ime_keydown_outcome = 0;
    return;
  }
  emit_key(owner, 10, (int)mods, code, 0, @"");
}
@end
@interface GPApplicationDelegate : NSObject <NSApplicationDelegate>
@end
@implementation GPApplicationDelegate
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
  (void)sender;
  if (state == 1) { state = 2; emit(nil, 15, 0, 0, 0, 0, 0); }
  return NSTerminateCancel;
}
@end
static GPApplicationDelegate *app_delegate;
static NSPasteboard *clipboard_pasteboard(void) {
#ifdef GPUI_TESTING
  if (test_clipboard) return test_clipboard;
#endif
  return NSPasteboard.generalPasteboard;
}
static void destroy(GPWindow *w) {
  w.closing = YES;
  // Drop queued callbacks for this generation before the terminal notification.
  NSIndexSet *indices = [events indexesOfObjectsPassingTest:^BOOL(NSDictionary *e, NSUInteger i, BOOL *stop) {
    (void)i; (void)stop; return [e[@"token"] longLongValue] == w.token;
  }];
  [events removeObjectsAtIndexes:indices];
  NSIndexSet *text_indices = [text_events indexesOfObjectsPassingTest:^BOOL(NSDictionary *e, NSUInteger i, BOOL *stop) {
    (void)i; (void)stop; return [e[@"token"] longLongValue] == w.token;
  }];
  [text_events removeObjectsAtIndexes:text_indices];
  w.text_armed = NO;
  w.text_epoch = 0;
  w.window.delegate = nil;
  ((GPView *)w.window.contentView).owner = nil;
  w.window.contentView.layer = nil;
  w.surface = nil;
  [w.window close];
  emit(w, 13, 0, 0, 0, 0, 0);
  [windows removeObjectForKey:@(w.token)];
  w.window = nil;
}
static int setup_gpu(void) {
  white_mask_texture = nil;
  device = MTLCreateSystemDefaultDevice();
  if (!device) return 16;
  queue = [device newCommandQueue];
  NSString *source = @"#include <metal_stdlib>\nusing namespace metal;\nstruct V { float4 p; float4 c; float2 uv; uint textured; uint padding; };\nstruct O { float4 p [[position]]; float4 c; float2 uv; uint textured [[flat]]; };\nvertex O vmain(const device V *v [[buffer(0)]], uint i [[vertex_id]]) { O o; o.p=v[i].p; o.c=v[i].c; o.uv=v[i].uv; o.textured=v[i].textured; return o; }\nfragment float4 fmain(O o [[stage_in]], texture2d<float> mask [[texture(0)]]) { constexpr sampler s(coord::normalized,address::clamp_to_edge,filter::linear); float coverage=o.textured ? mask.sample(s,o.uv).r : 1.0; return float4(o.c.rgb,o.c.a*coverage); }";
  NSError *error = nil;
  id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
  if (!library || !queue) return 16;
  MTLRenderPipelineDescriptor *desc = [MTLRenderPipelineDescriptor new];
  desc.vertexFunction = [library newFunctionWithName:@"vmain"];
  desc.fragmentFunction = [library newFunctionWithName:@"fmain"];
  MTLRenderPipelineColorAttachmentDescriptor *color = desc.colorAttachments[0];
  color.pixelFormat = MTLPixelFormatBGRA8Unorm;
  color.blendingEnabled = YES;
  color.sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
  color.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
  color.sourceAlphaBlendFactor = MTLBlendFactorOne;
  color.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
  pipeline = [device newRenderPipelineStateWithDescriptor:desc error:&error];
  if (!pipeline) return 16;
  MTLTextureDescriptor *white_desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm width:1 height:1 mipmapped:NO];
  white_desc.usage = MTLTextureUsageShaderRead;
  white_desc.storageMode = MTLStorageModeShared;
  white_mask_texture = [device newTextureWithDescriptor:white_desc];
  if (!white_mask_texture) return 16;
  const uint8_t white = 255;
  [white_mask_texture replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:&white bytesPerRow:1];
  return 0;
}
static int recover_renderer(void) {
  /* Frames are submitted synchronously, so no command buffer retains a layer
   * or drawable when this operation begins. Replace the shared device graph,
   * then attach the new device to every live window before publishing success. */
  pipeline = nil;
  queue = nil;
  device = nil;
  white_mask_texture = nil;
  int status = setup_gpu();
  if (status) {
    pipeline = nil;
    queue = nil;
    device = nil;
    white_mask_texture = nil;
    return status;
  }
  for (GPWindow *window in windows.allValues) {
    window.surface.device = device;
    resize_surface(window);
  }
  return 0;
}
typedef struct { float position[4], color[4], uv[2]; uint32_t textured, padding; } Vertex;
_Static_assert(sizeof(Vertex) == 48, "Metal vertex layout must be 48 bytes");
typedef struct { Vertex v[6]; MTLScissorRect clip; NSUInteger texture_index; } Draw;
static double n(NSDictionary *d, NSString *key) { return [d[key] doubleValue]; }
static CGRect rect(NSDictionary *d) { return CGRectMake(n(d,@"x"), n(d,@"y"), n(d,@"width"), n(d,@"height")); }
static BOOL valid_json_number(id value) {
  return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() && isfinite([value doubleValue]);
}
static BOOL valid_json_numeric_fields(NSDictionary *object, NSArray<NSString *> *keys) {
  if (![object isKindOfClass:NSDictionary.class]) return NO;
  for (NSString *key in keys) if (!valid_json_number(object[key])) return NO;
  return YES;
}
static int text_native_status(int status) {
  if (status == 3 || status == 17) return 13;
  if (status == 7 || status == 11 || status == 12 || status == 15 || status == 16) return 5;
  if (status == 14 || status == 8 || status == 10 || status == 2) return 9;
  return status ? 16 : 0;
}
static id<MTLTexture> text_mask_texture(NSString *text, double font_size, double scale,
                                        CGRect bounds, NSPoint origin, CGRect *draw_bounds,
                                        float uv[4], BOOL *empty, int *error) {
  NSData *utf8 = nil;
  *empty = NO;
  *error = 0;
  if (![text isKindOfClass:NSString.class] || text.length > 4096 ||
      !isfinite(font_size) || font_size <= 0 || font_size > 32 ||
      !isfinite(scale) || scale < 1 || scale > 8) {
    *error = 5; return nil;
  }
  utf8 = [text dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
  if (!utf8 || utf8.length > 4096) { *error = 5; return nil; }
  GpuiMacosTextMask mask = {0};
  int native_status = gpui_macos_text_raster_v1(utf8.bytes, (int32_t)utf8.length, font_size, scale, &mask);
  if (native_status) { *error = text_native_status(native_status); gpui_macos_text_raster_free(&mask); return nil; }
  if (!mask.width || !mask.height || !mask.pixels) {
    *empty = YES; gpui_macos_text_raster_free(&mask); return nil;
  }
  if (mask.width > 16384 || mask.height > 2048 || (int64_t)mask.width * mask.height > 8 * 1024 * 1024 || mask.stride < mask.width) {
    *error = 13; gpui_macos_text_raster_free(&mask); return nil;
  }
  double left = origin.x + mask.left, top = origin.y + mask.top;
  double right = left + (double)mask.width / scale, bottom = top + (double)mask.height / scale;
  if (!isfinite(left) || !isfinite(top) || !isfinite(right) || !isfinite(bottom)) {
    *error = 5; gpui_macos_text_raster_free(&mask); return nil;
  }
  double crop_left = MAX(0, ceil((CGRectGetMinX(bounds) - left) * scale - 0.5));
  double crop_top = MAX(0, ceil((CGRectGetMinY(bounds) - top) * scale - 0.5));
  double crop_right = MIN(mask.width, ceil((CGRectGetMaxX(bounds) - left) * scale - 0.5));
  double crop_bottom = MIN(mask.height, ceil((CGRectGetMaxY(bounds) - top) * scale - 0.5));
  if (crop_right <= crop_left || crop_bottom <= crop_top) {
    *empty = YES; gpui_macos_text_raster_free(&mask); return nil;
  }
  NSUInteger x0 = (NSUInteger)crop_left, y0 = (NSUInteger)crop_top;
  NSUInteger width = (NSUInteger)(crop_right - crop_left), height = (NSUInteger)(crop_bottom - crop_top);
  if ((int64_t)width * height > 8 * 1024 * 1024) { *error = 13; gpui_macos_text_raster_free(&mask); return nil; }
  NSMutableData *cropped = [NSMutableData dataWithLength:width * height];
  if (!cropped) { *error = 13; gpui_macos_text_raster_free(&mask); return nil; }
  const uint8_t *source = mask.pixels;
  uint8_t *destination = cropped.mutableBytes;
  for (NSUInteger y = 0; y < height; y++)
    memcpy(destination + y * width, source + (y0 + y) * (NSUInteger)mask.stride + x0, width);
  MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm width:width height:height mipmapped:NO];
  descriptor.usage = MTLTextureUsageShaderRead;
  descriptor.storageMode = MTLStorageModeShared;
  id<MTLTexture> texture = [device newTextureWithDescriptor:descriptor];
  if (!texture) { *error = 13; gpui_macos_text_raster_free(&mask); return nil; }
  [texture replaceRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0 withBytes:cropped.bytes bytesPerRow:width];
  *draw_bounds = CGRectMake(left + (double)x0 / scale, top + (double)y0 / scale,
                            (double)width / scale, (double)height / scale);
  uv[0] = 0; uv[1] = 0; uv[2] = 1; uv[3] = 1;
  gpui_macos_text_raster_free(&mask);
  return texture;
}
static int present(GPWindow *w, const uint8_t *bytes, int32_t len) {
  if (!device || !queue || !pipeline) return 16;
  NSDictionary *scene = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:bytes length:len] options:0 error:nil];
  if (![scene isKindOfClass:NSDictionary.class] || [scene[@"schema_version"] intValue] != 1) return 5;
  if ([scene[@"resources"] count] != 0) return 9;
  resize_surface(w);
  CGRect viewport = rect(scene[@"viewport"]);
  if (viewport.origin.x != 0 || viewport.origin.y != 0 || viewport.size.width <= 0 || viewport.size.height <= 0 ||
      viewport.size.width != w.window.contentView.bounds.size.width || viewport.size.height != w.window.contentView.bounds.size.height ||
      n(scene,@"scale") != w.scale) return 5;
  NSArray *items = scene[@"items"];
  if (items.count > 65536) return 13;
  NSMutableData *data = [NSMutableData dataWithLength:sizeof(Draw) * items.count];
  if (!data) return 13;
  Draw *draws = data.mutableBytes;
  NSMutableArray<id<MTLTexture>> *textures = [NSMutableArray new];
  if (!white_mask_texture) return 16;
  [textures addObject:white_mask_texture];
  NSUInteger count = 0;
  NSUInteger text_allocation = 0;
  for (NSDictionary *item in items) {
    if (![item isKindOfClass:NSDictionary.class]) return 5;
    NSString *kind = item[@"kind"];
    if (![kind isKindOfClass:NSString.class]) return 5;
    BOOL is_text_run = [kind isEqual:@"text_run"];
    BOOL is_text = is_text_run || [kind isEqual:@"text"];
    if (!is_text && ![kind isEqual:@"quad"]) return 9;
    NSDictionary *bounds_value = item[@"bounds"];
    if (!valid_json_numeric_fields(bounds_value, @[@"x", @"y", @"width", @"height"])) return 5;
    CGRect item_bounds = rect(bounds_value), bounds = item_bounds, clip = viewport;
    if (CGRectGetWidth(item_bounds) < 0 || CGRectGetHeight(item_bounds) < 0 ||
        CGRectGetWidth(item_bounds) > 1e9 || CGRectGetHeight(item_bounds) > 1e9 ||
        fabs(CGRectGetMinX(item_bounds)) > 1e9 || fabs(CGRectGetMinY(item_bounds)) > 1e9) return 5;
    NSDictionary *transform = item[@"transform"], *color = item[@"color"];
    if (!valid_json_numeric_fields(transform, @[@"a", @"b", @"c", @"d", @"tx", @"ty"]) ||
        !valid_json_numeric_fields(color, @[@"red", @"green", @"blue", @"alpha"]) ||
        !valid_json_number(item[@"opacity"])) return 5;
    float uv[4] = {0, 0, 1, 1};
    NSUInteger texture_index = 0;
    if (is_text) {
      NSDictionary *origin_value = is_text_run ? item[@"text_origin"] : nil;
      if ((is_text_run && !valid_json_numeric_fields(origin_value, @[@"x", @"y"])) ||
          ![item[@"text"] isKindOfClass:NSString.class] || !valid_json_number(item[@"font_size"])) return 5;
      double origin_x = is_text_run ? n(origin_value, @"x") : CGRectGetMinX(item_bounds);
      double origin_y = is_text_run ? n(origin_value, @"y") : CGRectGetMinY(item_bounds);
      if (!isfinite(origin_x) || !isfinite(origin_y) || fabs(origin_x) > 1e9 || fabs(origin_y) > 1e9 ||
          CGRectGetWidth(item_bounds) > 2048 || CGRectGetHeight(item_bounds) > 128) return 13;
      double font_size = n(item, @"font_size");
      if (font_size <= 0 || font_size > 32) return 5;
      CGRect text_bounds = item_bounds;
      BOOL empty = NO;
      int text_error = 0;
      id<MTLTexture> texture = text_mask_texture(item[@"text"], font_size, w.scale,
          item_bounds, NSMakePoint(origin_x, origin_y), &text_bounds, uv, &empty, &text_error);
      if (text_error) return text_error;
      if (empty) continue;
      NSUInteger allocation = (NSUInteger)texture.width * texture.height;
      if (allocation > 8 * 1024 * 1024 - text_allocation) return 13;
      text_allocation += allocation;
      bounds = text_bounds;
      [textures addObject:texture];
      texture_index = textures.count - 1;
    }
    if (item[@"clip_chain_id"] != NSNull.null) {
      BOOL found = NO;
      for (NSDictionary *chain in scene[@"clip_chains"]) {
        if ([chain[@"id"] isEqual:item[@"clip_chain_id"]]) {
          found = YES;
          for (NSDictionary *r in chain[@"rects"]) clip = CGRectIntersection(clip, rect(r));
          break;
        }
      }
      if (!found) return 5;
    }
    if (CGRectIsEmpty(clip) || CGRectIsNull(clip)) continue;
    double s = w.scale;
    // A scissor pixel is covered when its sample center (i + 0.5) lies in the
    // logical half-open clip. Convert both edges against that sample lattice.
    long long left_i = (long long)ceil(CGRectGetMinX(clip)*s - 0.5);
    long long top_i = (long long)ceil(CGRectGetMinY(clip)*s - 0.5);
    long long right_i = (long long)ceil(CGRectGetMaxX(clip)*s - 0.5);
    long long bottom_i = (long long)ceil(CGRectGetMaxY(clip)*s - 0.5);
    long long width_i = (long long)w.surface.drawableSize.width;
    long long height_i = (long long)w.surface.drawableSize.height;
    if (left_i < 0) left_i = 0; if (top_i < 0) top_i = 0;
    if (right_i < 0) right_i = 0; if (bottom_i < 0) bottom_i = 0;
    if (left_i > width_i) left_i = width_i; if (right_i > width_i) right_i = width_i;
    if (top_i > height_i) top_i = height_i; if (bottom_i > height_i) bottom_i = height_i;
    if (right_i <= left_i || bottom_i <= top_i) continue;
    NSUInteger left = (NSUInteger)left_i, top = (NSUInteger)top_i;
    NSUInteger right = (NSUInteger)right_i, bottom = (NSUInteger)bottom_i;
    Draw *draw = &draws[count++];
    draw->clip = (MTLScissorRect){left,top,right-left,bottom-top};
    draw->texture_index = texture_index;
    NSDictionary *t = transform, *c = color;
    double opacity = n(item, @"opacity");
    double red = n(c, @"red"), green = n(c, @"green");
    double blue = n(c, @"blue"), alpha = n(c, @"alpha");
    if (opacity < 0 || opacity > 1 || red < 0 || red > 255 || green < 0 || green > 255 ||
        blue < 0 || blue > 255 || alpha < 0 || alpha > 255) return 5;
    double xs[] = {CGRectGetMinX(bounds),CGRectGetMaxX(bounds),CGRectGetMinX(bounds),CGRectGetMinX(bounds),CGRectGetMaxX(bounds),CGRectGetMaxX(bounds)};
    double ys[] = {CGRectGetMinY(bounds),CGRectGetMinY(bounds),CGRectGetMaxY(bounds),CGRectGetMaxY(bounds),CGRectGetMinY(bounds),CGRectGetMaxY(bounds)};
    float us[] = {uv[0], uv[2], uv[0], uv[0], uv[2], uv[2]};
    float vs[] = {uv[1], uv[1], uv[3], uv[3], uv[1], uv[3]};
    for (int i = 0; i < 6; i++) {
      double x = n(t,@"a")*xs[i] + n(t,@"c")*ys[i] + n(t,@"tx");
      double y = n(t,@"b")*xs[i] + n(t,@"d")*ys[i] + n(t,@"ty");
      double px = 2*x/viewport.size.width-1, py = 1-2*y/viewport.size.height;
      if (!isfinite(px) || !isfinite(py) || fabs(px)>1e20 || fabs(py)>1e20) return 5;
      draw->v[i] = (Vertex){{(float)px,(float)py,0,1}, {(float)(red/255),(float)(green/255),(float)(blue/255),(float)(alpha/255*opacity)}, {us[i],vs[i]}, is_text ? 1u : 0u, 0};
    }
  }
  id<CAMetalDrawable> drawable = [w.surface nextDrawable];
  if (!drawable) return 15;
  MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
  pass.colorAttachments[0].texture = drawable.texture;
  pass.colorAttachments[0].loadAction = MTLLoadActionClear;
  pass.colorAttachments[0].storeAction = MTLStoreActionStore;
  pass.colorAttachments[0].clearColor = MTLClearColorMake(0.035,0.05,0.075,1);
  id<MTLCommandBuffer> command = [queue commandBuffer];
  id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];
  if (!command || !encoder) return 13;
  [encoder setRenderPipelineState:pipeline];
  for (NSUInteger i = 0; i < count; i++) {
    [encoder setScissorRect:draws[i].clip];
    [encoder setVertexBytes:draws[i].v length:sizeof(draws[i].v) atIndex:0];
    [encoder setFragmentTexture:textures[draws[i].texture_index] atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
  }
  [encoder endEncoding];
#ifdef GPUI_TESTING
  NSUInteger readback_width=drawable.texture.width, readback_height=drawable.texture.height;
  NSUInteger readback_stride=((readback_width*4+255)/256)*256;
  if (!readback_width || !readback_height || readback_width > 16384 || readback_height > 16384 ||
      readback_width * readback_height > 16 * 1024 * 1024) return 13;
  id<MTLBuffer> readback=[device newBufferWithLength:readback_stride*readback_height options:MTLResourceStorageModeShared];
  if (!readback) return 13;
  id<MTLBlitCommandEncoder> blit=[command blitCommandEncoder];
  [blit copyFromTexture:drawable.texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
    sourceSize:MTLSizeMake(readback_width,readback_height,1) toBuffer:readback destinationOffset:0
    destinationBytesPerRow:readback_stride destinationBytesPerImage:readback_stride*readback_height];
  [blit endEncoding];
#endif
  [command presentDrawable:drawable];
  [command commit];
  // First slice deliberately keeps one synchronous in-flight frame. No closure
  // retains MoonBit memory; teardown cannot race frame completion.
  [command waitUntilCompleted];
#ifdef GPUI_TESTING
  if (command.status == MTLCommandBufferStatusCompleted) {
    frame_width=readback_width; frame_height=readback_height; frame_stride=readback_stride;
    frame_pixels=[NSData dataWithBytes:readback.contents length:frame_stride*frame_height];
    frame_window_token=w.token; frame_scale=w.scale;
  }
#endif
  return command.status == MTLCommandBufferStatusCompleted ? 0 : 16;
}
// LSUIElement bundles already have Accessory policy. AppKit returns NO when
// asked to set that same policy, so request a transition only when needed.
static BOOL ensure_background_policy(NSApplication *application) {
  if (application.activationPolicy != NSApplicationActivationPolicyAccessory &&
      ![application setActivationPolicy:NSApplicationActivationPolicyAccessory])
    return NO;
  return application.activationPolicy == NSApplicationActivationPolicyAccessory;
}

static int32_t native_call(int32_t op, int64_t token, double x, double y, const uint8_t *bytes, int32_t len) {
  if (![NSThread isMainThread]) return 18;
  if (len < 0 || len > 16*1024*1024 || (len && !bytes)) return 5;
  @autoreleasepool {
    if (op == 1 || op == 17) {
      if (state) return state == 2 ? 19 : 12;
      int status = setup_gpu();
      if (status) { pipeline=nil; queue=nil; device=nil; return status; }
      [NSApplication sharedApplication];
      background_host = op == 17;
      if (background_host) {
        if (!ensure_background_policy(NSApp)) {
          white_mask_texture=nil; pipeline=nil; queue=nil; device=nil; background_host=NO;
          return 9;
        }
      } else {
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
      }
      app_delegate = [GPApplicationDelegate new]; NSApp.delegate = app_delegate;
      windows = [NSMutableDictionary new]; events = [NSMutableArray new]; current=nil; overflow=NO;
      text_events = [NSMutableArray new]; text_overflow=NO; next_text_epoch=0;
      [NSApp finishLaunching]; state = 1; host_epoch++;
      return 0;
    }
    if (op == 0) return token == host_epoch ? 0 : 10;
    if (op == 2) {
      if (!state) return 0;
      for (GPWindow *w in windows.allValues) destroy(w);
      events=nil; current=nil; text_result=nil; windows=nil; text_events=nil; text_overflow=NO; white_mask_texture=nil; pipeline=nil; queue=nil; device=nil;
#ifdef GPUI_TESTING
      [test_clipboard releaseGlobally]; test_clipboard=nil;
#endif
      NSApp.delegate=nil; app_delegate=nil; background_host=NO; state=0;
      return 0;
    }
    if (!state) return 1;
    if (op == 3) {
      if (state == 2) return 19;
      if (!isfinite(x) || !isfinite(y) || x < 1 || y < 1 || x > 8192 || y > 8192) return 5;
      if (next_token == INT64_MAX || windows.count >= 64) return 13;
      NSString *title = [[NSString alloc] initWithBytes:bytes length:len encoding:NSUTF8StringEncoding];
      if (!title) return 17;
      GPWindow *w = [GPWindow new];
      w.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,x,y) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
      if (!w.window) return 14;
      w.window.releasedWhenClosed = NO;
      w.window.animationBehavior = NSWindowAnimationBehaviorNone;
      w.window.contentMinSize = NSMakeSize(128,128);
      w.token = ++next_token; w.scale = w.window.backingScaleFactor;
      GPView *view = [[GPView alloc] initWithFrame:NSMakeRect(0,0,x,y)];
      view.owner=w; view.wantsLayer=YES;
      w.surface=[CAMetalLayer layer]; w.surface.device=device; w.surface.pixelFormat=MTLPixelFormatBGRA8Unorm;
      w.surface.allowsNextDrawableTimeout=YES;
#ifdef GPUI_TESTING
      w.surface.framebufferOnly=NO;
#endif
      view.layer=w.surface;
      w.window.contentView=view; w.window.delegate=w; w.window.title=title;
      windows[@(w.token)]=w; result_token=w.token;
      resize_surface(w); emit(w,1,0,0,0,0,0);
      [w.window makeFirstResponder:view];
      if (!background_host) {
        [w.window center]; [w.window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
      }
      return 0;
    }
    if (op == 6) {
      if (!isfinite(x) || x < 0 || x > 250) return 5;
      current=nil;
      if (!events.count) {
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:x/1000];
        NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:until inMode:NSDefaultRunLoopMode dequeue:YES];
        if (event) [NSApp sendEvent:event];
        [NSApp updateWindows];
      }
      if (overflow) { overflow=NO; return 13; }
      if (events.count) { current=events[0]; [events removeObjectAtIndex:0]; }
      return 0;
    }
    if (op == 10) { emit(nil,14,0,0,0,0,0); return 0; }
    if (op == 12) {
      switch ((int)x) { case 0: [[NSCursor arrowCursor] set]; break; case 1: [[NSCursor pointingHandCursor] set]; break; case 2: [[NSCursor IBeamCursor] set]; break; default: return 9; }
      return 0;
    }
    if (op == 13) {
      current=nil;
      NSString *text = [clipboard_pasteboard() stringForType:NSPasteboardTypeString] ?: @"";
      text_result = [text dataUsingEncoding:NSUTF8StringEncoding];
      return text_result.length <= 16*1024*1024 ? 0 : 13;
    }
    if (op == 14) {
      NSString *text = [[NSString alloc] initWithBytes:bytes length:len encoding:NSUTF8StringEncoding];
      if (!text) return 17;
      NSPasteboard *pasteboard = clipboard_pasteboard();
      [pasteboard clearContents];
      return [pasteboard setString:text forType:NSPasteboardTypeString] ? 0 : 12;
    }
    if (op == 11) { if (state == 1) { state=2; emit(nil,15,0,0,0,0,0); } return 0; }
    GPWindow *w=windows[@(token)];
    if (!w) return op == 8 && token > 0 && token <= next_token ? 0 : 10;
    switch (op) {
      case 18:
        if (!background_host) return 9;
        [w.window orderBack:nil]; return 0;
      case 4: {
        NSString *title=[[NSString alloc] initWithBytes:bytes length:len encoding:NSUTF8StringEncoding];
        if (!title) return 17; w.window.title=title; return 0;
      }
      case 5:
        if (!isfinite(x) || !isfinite(y) || x < 1 || y < 1 || x > 8192 || y > 8192) return 5;
        [w.window setContentSize:NSMakeSize(x,y)]; return 0;
      case 7: [w.window performClose:nil]; return 0;
      case 8:
        // Keep the window live if its terminal event cannot be queued. Events
        // for this token will be removed during destruction, freeing a slot.
        if (events.count >= 4096) {
          BOOL frees_slot = NO;
          for (NSDictionary *event in events) {
            if ([event[@"token"] longLongValue] == token) { frees_slot = YES; break; }
          }
          if (!frees_slot) return 13;
        }
        destroy(w); return 0;
      case 9: return present(w,bytes,len);
      case 16: return recover_renderer();
      case 15: resize_surface(w); current=@{@"width":@(w.window.contentView.bounds.size.width), @"height":@(w.window.contentView.bounds.size.height), @"scale":@(w.scale)}; return 0;
      case 19: {
        if (x != 0.0 && x != 1.0) return 5;
        /* A portable text-input session owns enablement while it is armed. */
        if (w.text_armed) return 12;
        GPView *view = (GPView *)w.window.contentView;
        if (x == 0.0) {
          [view unmarkText];
          w.ime_enabled = NO;
        } else {
          w.ime_enabled = YES;
          [w.window makeFirstResponder:view];
        }
        return 0;
      }
      case 20: {
        if (!isfinite(x) || !isfinite(y) || len != 8 || !bytes) return 5;
        uint32_t width = (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8) |
                         ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
        uint32_t height = (uint32_t)bytes[4] | ((uint32_t)bytes[5] << 8) |
                          ((uint32_t)bytes[6] << 16) | ((uint32_t)bytes[7] << 24);
        if (x < -8192.0 || y < -8192.0 || x > 8192.0 || y > 8192.0 ||
            width == 0 || height == 0 || width > 8192 || height > 8192)
          return 5;
        w.ime_caret = NSMakeRect(x, y, (double)width, (double)height);
        return 0;
      }
      case 21: {
        if (x != 0.0 && x != 1.0) return 5;
        if (!w.ime_enabled) return 9;
        GPView *view = (GPView *)w.window.contentView;
        if (x != 0.0 && view.marked && view.marked_text.length > 0) {
          [view insertText:view.marked_text replacementRange:view.marked_range];
        } else {
          [view unmarkText];
        }
        return 0;
      }
      default: return 9;
    }
  }
}
static int64_t native_integer(int32_t field) {
  if (![NSThread isMainThread]) return 0;
  if (field >= 100) { NSData *text = current[@"text"] ?: text_result; return field-100 < (int)text.length ? ((const uint8_t *)text.bytes)[field-100] : 0; }
  switch(field) {
    case 0:return result_token; case 1:return [current[@"kind"] longLongValue];
    case 2:return [current[@"token"] longLongValue]; case 3:return [current[@"seq"] longLongValue];
    case 4:return [current[@"mods"] longLongValue]; case 5:return [current[@"code"] longLongValue];
    case 6:return [current[@"repeat"] longLongValue]; case 7:return 1;
    case 8:return [(current[@"text"] ?: text_result) length]; case 9:return host_epoch; default:return 0;
  }
}
enum { MACOS_DISPLAY_CAPACITY = 16, MACOS_DISPLAY_FIELDS = 14 };
static BOOL valid_screen_rect(NSRect rect) {
  return isfinite(NSMinX(rect)) && isfinite(NSMinY(rect)) &&
      isfinite(NSWidth(rect)) && isfinite(NSHeight(rect)) &&
      NSWidth(rect) > 0 && NSHeight(rect) > 0;
}
static BOOL screen_display_id(NSScreen *screen, CGDirectDisplayID *display) {
  id value = screen.deviceDescription[@"NSScreenNumber"];
  if (![value isKindOfClass:NSNumber.class]) return NO;
  double number = [value doubleValue];
  if (!isfinite(number) || number < 0 || number > UINT32_MAX ||
      floor(number) != number) return NO;
  *display = (CGDirectDisplayID)number;
  return YES;
}
static NSWindow *host_key_window(void) {
  NSWindow *key = NSApp.keyWindow;
  if (!key) return nil;
  for (GPWindow *window in windows.allValues)
    if (!window.closing && window.window == key) return key;
  return nil;
}
int32_t gpui_macos_display_snapshot_v1(int64_t host, double *records,
                                      int32_t capacity) {
  if (![NSThread isMainThread]) return -18;
  if (!records || capacity != MACOS_DISPLAY_CAPACITY * MACOS_DISPLAY_FIELDS)
    return -5;
  if (!state) return -1;
  if (state == 2) return -19;
  if (host != host_epoch) return -10;
  @autoreleasepool {
    NSArray<NSScreen *> *screens = NSScreen.screens;
    if (![screens isKindOfClass:NSArray.class]) return -20;
    NSUInteger count = screens.count;
    if (count > MACOS_DISPLAY_CAPACITY) return -13;
    double copied[MACOS_DISPLAY_CAPACITY * MACOS_DISPLAY_FIELDS] = {0};
    CGDirectDisplayID identifiers[MACOS_DISPLAY_CAPACITY] = {0};
    NSWindow *key_window = host_key_window();
    NSScreen *key_screen = key_window.screen;
    CGDirectDisplayID key_display = 0;
    if (key_screen && !screen_display_id(key_screen, &key_display))
      return -17;
    for (NSUInteger index = 0; index < count; index++) {
      NSScreen *screen = screens[index];
      if (![screen isKindOfClass:NSScreen.class]) return -20;
      CGDirectDisplayID display = 0;
      if (!screen_display_id(screen, &display)) return -17;
      if (!CGDisplayIsOnline(display)) return -12;
      NSRect frame = screen.frame;
      NSRect visible = screen.visibleFrame;
      double scale = screen.backingScaleFactor;
      if (!valid_screen_rect(frame) || !valid_screen_rect(visible) ||
          !isfinite(scale) || scale <= 0 || scale > 8) return -20;
      CGDisplayModeRef mode = CGDisplayCopyDisplayMode(display);
      if (!mode) return CGDisplayIsOnline(display) ? -20 : -12;
      size_t mode_width = CGDisplayModeGetPixelWidth(mode);
      size_t mode_height = CGDisplayModeGetPixelHeight(mode);
      double refresh = CGDisplayModeGetRefreshRate(mode);
      CGDisplayModeRelease(mode);
      if (!mode_width || !mode_height || mode_width > INT32_MAX ||
          mode_height > INT32_MAX || !isfinite(refresh) || refresh < 0 ||
          refresh > 1000) return -20;
      int base = (int)index * MACOS_DISPLAY_FIELDS;
      copied[base] = NSMinX(frame);
      copied[base + 1] = NSMinY(frame);
      copied[base + 2] = NSWidth(frame);
      copied[base + 3] = NSHeight(frame);
      copied[base + 4] = NSMinX(visible);
      copied[base + 5] = NSMinY(visible);
      copied[base + 6] = NSWidth(visible);
      copied[base + 7] = NSHeight(visible);
      copied[base + 8] = scale;
      copied[base + 9] = (double)mode_width;
      copied[base + 10] = (double)mode_height;
      copied[base + 11] = refresh;
      copied[base + 12] = CGDisplayIsMain(display) ? 1 : 0;
      copied[base + 13] = key_screen && display == key_display ? 1 : 0;
      identifiers[index] = display;
      if (!CGDisplayIsOnline(display)) return -12;
    }
    NSArray<NSScreen *> *current_screens = NSScreen.screens;
    if (![current_screens isKindOfClass:NSArray.class] ||
        current_screens.count != count) return -12;
    for (NSUInteger index = 0; index < count; index++) {
      CGDirectDisplayID current_display = 0;
      if (!screen_display_id(current_screens[index], &current_display))
        return -12;
      if (current_display != identifiers[index] ||
          !CGDisplayIsOnline(current_display)) return -12;
    }
    if (count) memcpy(records, copied, count * MACOS_DISPLAY_FIELDS * sizeof(double));
    return (int32_t)count;
  }
}
static double native_number(int32_t field) {
  if (![NSThread isMainThread]) return 0;
  NSArray *keys=@[@"scale",@"x",@"y",@"width",@"height"];
  return field >= 0 && field < 5 ? [current[keys[field]] doubleValue] : 0;
}
const GpuiApi *gpui_macos_api_v1(void) {
  static const GpuiApi api={1,sizeof(GpuiApi),native_call,native_integer,native_number};
  return &api;
}

/* Portable text-input transport. A session owns enablement, epoch, and the
 * ordered record stream; the ordinary event queue keeps non-composition
 * records. Epochs are host-issued and never reused. */
static BOOL text_epoch_current(GPWindow *w, int64_t epoch) {
  return w && w.text_armed && epoch == w.text_epoch;
}
static void drop_text_events(GPWindow *w, BOOL other_epochs_only) {
  if (!w) return;
  int64_t token = w.token;
  int64_t epoch = w.text_epoch;
  NSIndexSet *indices = [text_events indexesOfObjectsPassingTest:^BOOL(NSDictionary *e, NSUInteger i, BOOL *stop) {
    (void)i; (void)stop;
    if ([e[@"token"] longLongValue] != token) return NO;
    return !other_epochs_only || [e[@"epoch"] longLongValue] != epoch;
  }];
  [text_events removeObjectsAtIndexes:indices];
}
int32_t gpui_macos_text_available_v1(void) { return 1; }
int32_t gpui_macos_text_session_v1(int32_t op, int64_t token, int64_t epoch,
                                   double *fields, const uint8_t *bytes,
                                   int32_t length) {
  if (![NSThread isMainThread]) return 18;
  if (length < 0 || (length > 0 && !bytes)) return 5;
  @autoreleasepool {
    if (!state) return 1;
    GPWindow *w = windows[@(token)];
    if (!w || w.closing) return 14;
    GPView *view = (GPView *)w.window.contentView;
    switch (op) {
      case 1: {
        if (w.text_armed) return 12;
        if (next_text_epoch == INT64_MAX) return 13;
        w.text_armed = YES;
        w.text_epoch = ++next_text_epoch;
        w.text_sequence = 0;
        [view resetImeState];
        w.ime_enabled = YES;
        [w.window makeFirstResponder:view];
        drop_text_events(w, NO);
        if (fields) fields[0] = (double)w.text_epoch;
        return 0;
      }
      case 2: {
        if (!text_epoch_current(w, epoch)) return 10;
        if (!fields) return 5;
        double x = fields[0], y = fields[1], width = fields[2], height = fields[3];
        if (!isfinite(x) || !isfinite(y) || !isfinite(width) || !isfinite(height))
          return 5;
        if (x < -8192.0 || y < -8192.0 || x > 8192.0 || y > 8192.0 ||
            width <= 0.0 || height <= 0.0 || width > 8192.0 || height > 8192.0)
          return 5;
        w.ime_caret = NSMakeRect(x, y, width, height);
        return 0;
      }
      case 3: {
        if (!text_epoch_current(w, epoch)) return 10;
        if (next_text_epoch == INT64_MAX) return 13;
        [view resetImeState];
        w.text_epoch = ++next_text_epoch;
        /* Records from the replaced epoch must not arrive after cancellation. */
        drop_text_events(w, YES);
        if (fields) fields[0] = (double)w.text_epoch;
        return 0;
      }
      case 4: {
        if (!text_epoch_current(w, epoch)) return 10;
        [view resetImeState];
        w.ime_enabled = NO;
        w.text_armed = NO;
        w.text_epoch = 0;
        drop_text_events(w, NO);
        return 0;
      }
      default: return 5;
    }
  }
}
int32_t gpui_macos_text_next_v1(int64_t token, int64_t epoch, int32_t timeout_ms,
                                double *fields, uint8_t *payload,
                                int32_t capacity) {
  if (![NSThread isMainThread]) return 18;
  if (!fields || !payload || capacity < 0 || capacity > 16*1024*1024) return 5;
  if (timeout_ms < 0 || timeout_ms > 250) return 5;
  @autoreleasepool {
    if (!state) return 1;
    GPWindow *w = windows[@(token)];
    if (!w || w.closing) return 14;
    if (!text_epoch_current(w, epoch)) return 10;
    fields[0] = 0.0;
    NSInteger index = -1;
    for (NSInteger attempt = 0; attempt < 2 && index < 0; attempt++) {
      for (NSUInteger i = 0; i < text_events.count; i++) {
        NSDictionary *record = text_events[i];
        if ([record[@"token"] longLongValue] == token &&
            [record[@"epoch"] longLongValue] == epoch) {
          index = (NSInteger)i;
          break;
        }
      }
      if (index < 0 && attempt == 0 && timeout_ms > 0) {
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:timeout_ms/1000.0];
        NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:until inMode:NSDefaultRunLoopMode dequeue:YES];
        if (event) [NSApp sendEvent:event];
        [NSApp updateWindows];
      }
    }
    if (text_overflow) { text_overflow = NO; return 13; }
    if (index < 0) return 0;
    NSDictionary *record = text_events[(NSUInteger)index];
    NSData *text = record[@"text"] ?: [NSData data];
    if (text.length > (NSUInteger)capacity) return 13;
    [text_events removeObjectAtIndex:(NSUInteger)index];
    fields[0] = 1.0;
    fields[1] = [record[@"kind"] doubleValue];
    fields[2] = [record[@"seq"] doubleValue];
    fields[3] = [record[@"epoch"] doubleValue];
    fields[4] = [record[@"cursor"] doubleValue];
    fields[5] = (double)text.length;
    if (text.length) memcpy(payload, text.bytes, text.length);
    return 0;
  }
}

/* Opt-in E2E access to the last completed native Metal frame. Pixel copying
 * canonicalizes the private BGRA drawable bytes to top-left RGBA8. */
int32_t gpui_macos_test_frame_meta_v1(int64_t window, double *output) {
#ifdef GPUI_TESTING
  if (![NSThread isMainThread]) return 18;
  const char *enabled = getenv("GPUI_NATIVE_E2E");
  if (!enabled || strcmp(enabled, "1") != 0) return 9;
  if (!output) return 5;
  GPWindow *target = windows[@(window)];
  if (!target || !target.window) return 10;
  if (!frame_pixels || frame_window_token != window) return 12;
  if (!frame_width || !frame_height || frame_width > 16384 || frame_height > 16384 ||
      frame_width * frame_height > 16 * 1024 * 1024 || frame_stride < frame_width * 4 ||
      frame_pixels.length < frame_stride * frame_height) return 13;
  output[0] = (double)frame_width;
  output[1] = (double)frame_height;
  output[2] = frame_scale;
  return 0;
#else
  (void)window; (void)output;
  return 9;
#endif
}

int32_t gpui_macos_test_frame_copy_v1(int64_t window, uint8_t *output,
                                      int32_t capacity) {
#ifdef GPUI_TESTING
  if (![NSThread isMainThread]) return 18;
  const char *enabled = getenv("GPUI_NATIVE_E2E");
  if (!enabled || strcmp(enabled, "1") != 0) return 9;
  GPWindow *target = windows[@(window)];
  if (!target || !target.window) return 10;
  if (!frame_pixels || frame_window_token != window) return 12;
  NSUInteger pixels = frame_width * frame_height;
  if (!frame_width || !frame_height || frame_width > 16384 || frame_height > 16384 ||
      pixels > 16 * 1024 * 1024 || frame_stride < frame_width * 4 ||
      frame_pixels.length < frame_stride * frame_height || pixels * 4 > INT32_MAX) return 13;
  NSUInteger required = pixels * 4;
  if (!output || capacity < 0 || (NSUInteger)capacity != required) return 5;
  const uint8_t *source = frame_pixels.bytes;
  for (NSUInteger y = 0; y < frame_height; ++y) {
    for (NSUInteger x = 0; x < frame_width; ++x) {
      NSUInteger src = y * frame_stride + x * 4;
      NSUInteger dst = (y * frame_width + x) * 4;
      output[dst] = source[src + 2];
      output[dst + 1] = source[src + 1];
      output[dst + 2] = source[src];
      output[dst + 3] = source[src + 3];
    }
  }
  return 0;
#else
  (void)window; (void)output; (void)capacity;
  return 9;
#endif
}

/* Opt-in, window-scoped E2E events. They travel through NSWindow's normal
 * dispatch path and cannot target arbitrary desktop windows. */
int32_t gpui_macos_test_post_click_v1(int64_t token, double x, double y) {
#ifdef GPUI_TESTING
  if (![NSThread isMainThread]) return 18;
  const char *enabled = getenv("GPUI_NATIVE_E2E");
  if (!enabled || strcmp(enabled, "1") != 0) return 9;
  GPWindow *target = windows[@(token)];
  if (!target || !target.window || target.closing) return 10;
  NSView *content = target.window.contentView;
  if (!isfinite(x) || !isfinite(y) || x < 0 || y < 0 ||
      x >= content.bounds.size.width || y >= content.bounds.size.height)
    return 5;
  NSPoint location = [content convertPoint:NSMakePoint(x, y) toView:nil];
  NSTimeInterval timestamp = NSProcessInfo.processInfo.systemUptime;
  NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
      location:location modifierFlags:0 timestamp:timestamp
      windowNumber:target.window.windowNumber context:nil eventNumber:1
      clickCount:1 pressure:1.0];
  NSEvent *up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp
      location:location modifierFlags:0 timestamp:timestamp + 0.001
      windowNumber:target.window.windowNumber context:nil eventNumber:1
      clickCount:1 pressure:0.0];
  if (!down || !up) return 16;
  [target.window sendEvent:down];
  [target.window sendEvent:up];
  return 0;
#else
  (void)token; (void)x; (void)y;
  return 9;
#endif
}

int32_t gpui_macos_test_post_key_v1(int64_t token, int32_t key_code,
                                    int32_t modifier_bits,
                                    const uint8_t *bytes, int32_t length) {
#ifdef GPUI_TESTING
  if (![NSThread isMainThread]) return 18;
  const char *enabled = getenv("GPUI_NATIVE_E2E");
  if (!enabled || strcmp(enabled, "1") != 0) return 9;
  if (key_code < 0 || key_code > 127 || modifier_bits < 0 ||
      (modifier_bits & ~15) != 0) return 5;
  if (length < 0 || (length > 0 && !bytes) || length > 256) return 5;
  GPWindow *target = windows[@(token)];
  if (!target || !target.window || target.closing) return 10;
  NSString *characters = [[NSString alloc] initWithBytes:bytes
      length:(NSUInteger)length encoding:NSUTF8StringEncoding];
  if (!characters) return 17;
  NSUInteger flags = 0;
  if (modifier_bits & 1) flags |= NSEventModifierFlagShift;
  if (modifier_bits & 2) flags |= NSEventModifierFlagControl;
  if (modifier_bits & 4) flags |= NSEventModifierFlagOption;
  if (modifier_bits & 8) flags |= NSEventModifierFlagCommand;
  NSTimeInterval timestamp = NSProcessInfo.processInfo.systemUptime;
  NSEvent *down = [NSEvent keyEventWithType:NSEventTypeKeyDown
      location:NSZeroPoint modifierFlags:flags timestamp:timestamp
      windowNumber:target.window.windowNumber context:nil characters:characters
      charactersIgnoringModifiers:characters isARepeat:NO keyCode:(unsigned short)key_code];
  NSEvent *up = [NSEvent keyEventWithType:NSEventTypeKeyUp
      location:NSZeroPoint modifierFlags:flags timestamp:timestamp + 0.001
      windowNumber:target.window.windowNumber context:nil characters:characters
      charactersIgnoringModifiers:characters isARepeat:NO keyCode:(unsigned short)key_code];
  if (!down || !up) return 16;
  [target.window sendEvent:down];
  [target.window sendEvent:up];
  return 0;
#else
  (void)token; (void)key_code; (void)modifier_bits; (void)bytes; (void)length;
  return 9;
#endif
}

int32_t gpui_macos_test_post_composition_v1(int64_t token, int32_t kind,
                                            int32_t cursor,
                                            const uint8_t *bytes,
                                            int32_t length) {
#ifdef GPUI_TESTING
  if (![NSThread isMainThread]) return 18;
  const char *enabled = getenv("GPUI_NATIVE_E2E");
  if (!enabled || strcmp(enabled, "1") != 0) return 9;
  if (kind < 0 || kind > 3 || cursor < 0 || cursor > 16384) return 5;
  if (length < 0 || (length > 0 && !bytes) || length > 65536) return 5;
  GPWindow *target = windows[@(token)];
  if (!target || !target.window || target.closing) return 10;
  if (!target.ime_enabled) return 9;
  GPView *view = (GPView *)target.window.contentView;
  NSString *text = [[NSString alloc] initWithBytes:bytes
      length:(NSUInteger)length encoding:NSUTF8StringEncoding];
  if (!text) return 17;
  switch (kind) {
    case 0:
      [view resetImeState];
      break;
    case 1:
      [view setMarkedText:text
          selectedRange:NSMakeRange((NSUInteger)cursor, 0)
          replacementRange:NSMakeRange(NSNotFound, 0)];
      break;
    case 2:
      [view insertText:text replacementRange:NSMakeRange(NSNotFound, 0)];
      break;
    case 3:
      [view unmarkText];
      break;
  }
  return 0;
#else
  (void)token; (void)kind; (void)cursor; (void)bytes; (void)length;
  return 9;
#endif
}

int32_t gpui_macos_test_post_escape_v1(int64_t token) {
#ifdef GPUI_TESTING
  if (![NSThread isMainThread]) return 18;
  const char *enabled = getenv("GPUI_NATIVE_E2E");
  if (!enabled || strcmp(enabled, "1") != 0) return 9;
  GPWindow *target = windows[@(token)];
  if (!target || !target.window || target.closing) return 10;
  NSTimeInterval timestamp = NSProcessInfo.processInfo.systemUptime;
  NSEvent *down = [NSEvent keyEventWithType:NSEventTypeKeyDown
      location:NSZeroPoint modifierFlags:0 timestamp:timestamp
      windowNumber:target.window.windowNumber context:nil characters:@"\e"
      charactersIgnoringModifiers:@"\e" isARepeat:NO keyCode:53];
  NSEvent *up = [NSEvent keyEventWithType:NSEventTypeKeyUp
      location:NSZeroPoint modifierFlags:0 timestamp:timestamp + 0.001
      windowNumber:target.window.windowNumber context:nil characters:@"\e"
      charactersIgnoringModifiers:@"\e" isARepeat:NO keyCode:53];
  if (!down || !up) return 16;
  [target.window sendEvent:down];
  [target.window sendEvent:up];
  return 0;
#else
  (void)token;
  return 9;
#endif
}
