#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../../platform/macos/accessibility_abi.h"

extern void gpui_macos_ax_test_set_notification_hook(
    void (*hook)(id, NSAccessibilityNotificationName));

@interface GPWindow : NSObject <NSWindowDelegate>
@property int64_t token;
@end
@implementation GPWindow
@end

@interface GPView : NSView
@end
@implementation GPView
@end

@interface NSView (AXChildTest)
- (NSArray *)accessibilityChildren;
@end

/* The adapter's element classes are private to accessibility.m. */
@interface NSObject (GPUI_AXTestElement)
@property(readonly) int64_t bindingToken;
- (BOOL)isAccessibilityEditable;
- (NSRange)accessibilitySelectedTextRange;
- (NSInteger)accessibilityNumberOfCharacters;
- (NSString *)accessibilitySelectedText;
@end

static void fail(const char *message) {
  fprintf(stderr, "FAIL: %s\n", message);
  exit(1);
}

static void require(BOOL condition, const char *message) {
  if (!condition) fail(message);
}

static NSWindow *make_window(int64_t token) {
  NSWindow *window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(40, 60, 360, 200)
                styleMask:NSWindowStyleMaskTitled
                  backing:NSBackingStoreBuffered
                    defer:NO];
  GPView *view = [[GPView alloc] initWithFrame:NSMakeRect(0, 0, 360, 200)];
  GPWindow *delegate = [GPWindow new];
  delegate.token = token;
  window.contentView = view;
  window.delegate = delegate;
  objc_setAssociatedObject(window, @selector(make_window), delegate,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  [window orderFront:nil];
  return window;
}

static const char *payload_with_bounds(BOOL enabled, BOOL loading,
                                      BOOL focused, int activations,
                                      double left, double top, double width,
                                      double height) {
  static char bytes[512];
  snprintf(bytes, sizeof(bytes),
           "{\"version\":1,\"role\":\"button\","
           "\"name\":\"Run action\",\"left\":%.3f,\"top\":%.3f,"
           "\"width\":%.3f,\"height\":%.3f,\"enabled\":%s,"
           "\"loading\":%s,\"focused\":%s,\"activations\":%d,"
           "\"actions\":[\"Invoke\"]}",
           left, top, width, height,
           enabled ? "true" : "false", loading ? "true" : "false",
           focused ? "true" : "false", activations);
  return bytes;
}

static int32_t publish_raw_payload(NSWindow *window, int64_t existing,
                                   const char *bytes, int64_t *binding_out) {
  id delegate = window.delegate;
  int64_t token = 0;
  if ([delegate respondsToSelector:@selector(token)])
    token = ((int64_t (*)(id, SEL))[delegate methodForSelector:@selector(token)])(
        delegate, @selector(token));
  return gpui_macos_ax_publish_v1(
      token, existing, (const uint8_t *)bytes, (int32_t)strlen(bytes),
      binding_out);
}

static void assert_numeric_rejected(NSWindow *window, const char *version,
                                    const char *activations) {
  char bytes[512];
  snprintf(bytes, sizeof(bytes),
           "{\"version\":%s,\"role\":\"button\","
           "\"name\":\"Run action\",\"left\":20,\"top\":30,"
           "\"width\":180,\"height\":48,\"enabled\":true,"
           "\"loading\":false,\"focused\":false,\"activations\":%s,"
           "\"actions\":[\"Invoke\"]}",
           version, activations);
  int64_t binding = 0;
  int32_t status = publish_raw_payload(window, 0, bytes, &binding);
  require(status == 5 && binding == 0,
          "fractional, boolean, or out-of-range integer must be rejected");
}

static void test_integer_payload_validation(NSWindow *window) {
  const char *invalid_versions[] = {
      "1.0", "1.5", "4294967297", "true", "-1"};
  for (size_t index = 0;
       index < sizeof(invalid_versions) / sizeof(invalid_versions[0]); index++)
    assert_numeric_rejected(window, invalid_versions[index], "0");

  const char *invalid_activations[] = {
      "0.0", "-0.5", "1.5", "2147483647.5", "2147483647.000000001",
      "2147483648", "true", "-1"};
  for (size_t index = 0;
       index < sizeof(invalid_activations) / sizeof(invalid_activations[0]);
       index++)
    assert_numeric_rejected(window, "1", invalid_activations[index]);

  const char *valid_activations[] = {"0", "2147483647"};
  for (size_t index = 0;
       index < sizeof(valid_activations) / sizeof(valid_activations[0]);
       index++) {
    char bytes[512];
    snprintf(bytes, sizeof(bytes),
             "{\"version\":1,\"role\":\"button\","
             "\"name\":\"Run action\",\"left\":20,\"top\":30,"
             "\"width\":180,\"height\":48,\"enabled\":true,"
             "\"loading\":false,\"focused\":false,\"activations\":%s,"
             "\"actions\":[\"Invoke\"]}",
             valid_activations[index]);
    int64_t binding = 0;
    require(publish_raw_payload(window, 0, bytes, &binding) == 0 && binding > 0,
            "valid integer count boundary should publish");
    require(gpui_macos_ax_revoke_v1(401, binding) == 0,
            "integer boundary fixture should revoke cleanly");
  }
}

static int64_t publish_with_bounds(NSWindow *window, int64_t existing,
                                   BOOL enabled, BOOL loading, BOOL focused,
                                   int activations, double left, double top,
                                   double width, double height) {
  id delegate = window.delegate;
  int64_t token = 0;
  if ([delegate respondsToSelector:@selector(token)])
    token = ((int64_t (*)(id, SEL))[delegate methodForSelector:@selector(token)])(
        delegate, @selector(token));
  const char *bytes = payload_with_bounds(enabled, loading, focused,
                                          activations, left, top, width, height);
  int64_t binding = 0;
  int32_t result = gpui_macos_ax_publish_v1(
      token, existing, (const uint8_t *)bytes, (int32_t)strlen(bytes), &binding);
  if (result != 0 || binding <= 0) {
    fprintf(stderr, "publish failed: status=%d window=%lld binding=%lld\n",
            result, (long long)token, (long long)binding);
    fail("publish should return a binding");
  }
  return binding;
}

static int64_t publish(NSWindow *window, int64_t existing, BOOL enabled,
                       BOOL loading, BOOL focused, int activations) {
  return publish_with_bounds(window, existing, enabled, loading, focused,
                             activations, 20, 30, 180, 48);
}

static id child(NSWindow *window) {
  return [((GPView *)window.contentView).accessibilityChildren firstObject];
}

static void test_projection_and_press(NSWindow *window, int64_t *binding_out) {
  int64_t binding = publish(window, 0, YES, NO, YES, 0);
  id button = child(window);
  require(button != nil, "the AppKit view should expose one AX child");
  require([button isAccessibilityElement], "published child should be live");
  require([[button accessibilityRole] isEqualToString:NSAccessibilityButtonRole],
          "role should be AX button");
  require([[button accessibilityLabel] isEqualToString:@"Run action"],
          "name should come from the shared snapshot");
  require([[button accessibilityTitle] isEqualToString:@"Run action"],
          "visible button name should also be the AX title");
  require([button accessibilityTopLevelUIElement] == window,
          "custom control should identify its owning top-level window");
  require([button isAccessibilityEnabled], "enabled should be projected");
  require([button isAccessibilityFocused], "focus should be projected");
  require([[button accessibilityHelp] containsString:@"Activations: 0"],
          "owner activation count should be observable");
  require([[button accessibilityHelp] containsString:@"Ready"],
          "loading state should be observable");
  NSRect frame = [button accessibilityFrame];
  require(!NSIsEmptyRect(frame), "AX frame should be in screen coordinates");
  require(fabs(frame.size.width - 180) < 1.0 &&
              fabs(frame.size.height - 48) < 1.0,
          "AX frame should preserve logical button dimensions");

  require([button accessibilityPerformPress], "enabled Invoke should enqueue");
  int64_t returned = 0;
  require(gpui_macos_ax_take_request_v1(401, &returned) == 1 &&
              returned == binding,
          "the owner should receive only the opaque binding token");
  require(gpui_macos_ax_take_request_v1(401, &returned) == 0,
          "one semantic request should be consumed once by the queue");
  *binding_out = binding;
}

static int focused_element_notifications = 0;
static int value_notifications = 0;
static int selection_notifications = 0;
static id last_focused_element;

static void notification_hook(id element,
                              NSAccessibilityNotificationName notification) {
  if ([notification isEqualToString:
                         NSAccessibilityFocusedUIElementChangedNotification]) {
    focused_element_notifications += 1;
    last_focused_element = element;
  } else if ([notification isEqualToString:
                                NSAccessibilityValueChangedNotification]) {
    value_notifications += 1;
  } else if ([notification
                 isEqualToString:NSAccessibilitySelectedTextChangedNotification]) {
    selection_notifications += 1;
  }
}

static id expected_focus_loss_target(NSWindow *window, id excluded,
                                     id previous) {
  id focused = [NSApp accessibilityApplicationFocusedUIElement];
  if (focused && focused != excluded && focused != previous) return focused;
  id ancestor = NSAccessibilityUnignoredAncestor(window.contentView);
  return ancestor ?: window.contentView;
}

static void test_focus_notifications(NSWindow *window) {
  int before = focused_element_notifications;

  int64_t binding = publish(window, 0, YES, NO, NO, 0);
  require(focused_element_notifications == before,
          "publishing an unfocused element should not emit a focus change");
  binding = publish(window, binding, YES, NO, YES, 0);
  require(focused_element_notifications == before + 1,
          "gaining AX focus should notify app observers once");
  id focused = child(window);
  require(last_focused_element == focused,
          "focus notification should target the newly focused live AX element");
  binding = publish(window, binding, YES, NO, YES, 1);
  require(focused_element_notifications == before + 1,
          "an unchanged focused element should not repeat the focus notification");
  id previous = child(window);
  id expected_loss_target = expected_focus_loss_target(window, previous, previous);
  publish(window, binding, YES, NO, NO, 1);
  require(focused_element_notifications == before + 2,
          "losing AX focus should notify app observers");
  require(last_focused_element == expected_loss_target &&
              last_focused_element != previous,
          "focus loss should target the current live focus or parent, not the stale child");

  binding = publish(window, binding, YES, NO, YES, 1);
  require(focused_element_notifications == before + 3,
          "regaining AX focus should notify app observers");
  id old_focused = child(window);
  binding = publish_with_bounds(window, binding, YES, NO, YES, 1, 20, 30,
                                181, 48);
  id replacement = child(window);
  require(replacement != old_focused && [replacement isAccessibilityElement],
          "focused geometry replacement should expose a new live AX element");
  require(focused_element_notifications == before + 4 &&
              last_focused_element == replacement,
          "focused replacement should notify with the new live AX element");

  id expected_revoke_target =
      expected_focus_loss_target(window, replacement, replacement);
  require(gpui_macos_ax_revoke_v1(401, binding) == 0,
          "focused AX element should revoke cleanly");
  require(focused_element_notifications == before + 5,
          "revoking a focused AX element should notify focus loss");
  require(last_focused_element == expected_revoke_target &&
              last_focused_element != replacement &&
              ![replacement isAccessibilityElement],
          "focused-element revocation should notify a live target after removing the stale child");

  binding = publish(window, 0, NO, NO, NO, 1);
  require(focused_element_notifications == before + 5,
          "disabled unfocused replacement should not repeat focus loss");
  require(![child(window) isAccessibilityEnabled],
          "disabled replacement should still be exposed as disabled");
  require(gpui_macos_ax_revoke_v1(401, 0) == 0,
          "focus notification test binding should revoke cleanly");
}

static void test_queue_capacity_and_resize(NSWindow *window, int64_t binding) {
  id button = child(window);
  for (int index = 0; index < 64; index++)
    require([button accessibilityPerformPress], "queue should accept 64 items");
  require(![button accessibilityPerformPress], "65th item should fail closed");

  [window setFrame:NSMakeRect(40, 60, 340, 190) display:YES];
  [[NSNotificationCenter defaultCenter]
      postNotificationName:NSWindowDidResizeNotification
                    object:window];
  int64_t returned = 0;
  require(gpui_macos_ax_take_request_v1(401, &returned) == 0,
          "resize should discard queued semantic work");
  require([button isAccessibilityElement],
          "a still-current semantic target should remain live after resize");
  require(fabs([button accessibilityFrame].size.width - 180) < 1.0,
          "the element frame should continue to track the owner view");
  require(gpui_macos_ax_revoke_v1(401, binding) == 0,
          "current binding should revoke cleanly");
  require(![button accessibilityPerformPress],
          "revoked object references should reject further Invoke");
  require(gpui_macos_ax_take_request_v1(401, &returned) == 0,
          "revocation should leave no queued request");
}

static void test_availability_update_purges_queue(NSWindow *window) {
  int64_t enabled_binding = publish(window, 0, YES, NO, NO, 0);
  id enabled = child(window);
  require([enabled accessibilityPerformPress],
          "enabled element should accept an event before state transition");

  int64_t disabled_binding =
      publish(window, enabled_binding, NO, NO, NO, 0);
  id disabled = child(window);
  require(disabled_binding != enabled_binding,
          "enabled state transition should replace the revocable binding");
  require(![enabled accessibilityPerformPress],
          "old element must reject after disabling");
  require(![disabled isAccessibilityEnabled],
          "disabled state should be observable");
  require(![disabled accessibilityPerformPress],
          "disabled semantic action should not enter the queue");
  int64_t returned = 0;
  require(gpui_macos_ax_take_request_v1(401, &returned) == 0,
          "availability transition should purge the earlier request");

  int64_t loading_binding =
      publish(window, disabled_binding, YES, YES, NO, 0);
  id loading = child(window);
  require(loading_binding != disabled_binding,
          "loading state transition should replace the binding");
  require(![loading accessibilityPerformPress],
          "loading semantic action should not enter the queue");
  require([[loading accessibilityHelp] containsString:@"Loading"],
          "loading state should be observable");
}

static id ax_child_with_role(NSWindow *window, NSString *role) {
  for (id element in ((GPView *)window.contentView).accessibilityChildren)
    if ([[element accessibilityRole] isEqualToString:role]) return element;
  return nil;
}

static int32_t publish_field_raw(NSWindow *window, int64_t existing,
                                 const char *bytes, int64_t *binding_out) {
  id delegate = window.delegate;
  int64_t token = 0;
  if ([delegate respondsToSelector:@selector(token)])
    token = ((int64_t (*)(id, SEL))[delegate methodForSelector:@selector(token)])(
        delegate, @selector(token));
  return gpui_macos_ax_publish_field_v1(
      token, existing, (const uint8_t *)bytes, (int32_t)strlen(bytes),
      binding_out);
}

static void make_field_payload(char *bytes, size_t size, const char *value,
                               int start, int length, BOOL focused,
                               BOOL editable) {
  snprintf(bytes, size,
           "{\"version\":1,\"role\":\"text_field\","
           "\"label\":\"Name\",\"value\":\"%s\","
           "\"left\":20,\"top\":90,\"width\":240,\"height\":32,"
           "\"focused\":%s,\"editable\":%s,"
           "\"selection_start\":%d,\"selection_length\":%d}",
           value, focused ? "true" : "false", editable ? "true" : "false",
           start, length);
}

static int64_t publish_field(NSWindow *window, int64_t existing,
                             const char *value, int start, int length,
                             BOOL focused, BOOL editable) {
  char bytes[4096];
  make_field_payload(bytes, sizeof(bytes), value, start, length, focused,
                     editable);
  int64_t binding = 0;
  int32_t status = publish_field_raw(window, existing, bytes, &binding);
  if (status != 0 || binding <= 0) {
    fprintf(stderr, "field publish failed: status=%d binding=%lld\n", status,
            (long long)binding);
    fail("field publish should return a binding");
  }
  return binding;
}

static void expect_field_rejected(NSWindow *window, int64_t existing,
                                  const char *bytes) {
  int64_t binding = -1;
  int32_t status = publish_field_raw(window, existing, bytes, &binding);
  require(status == 5, "invalid text-field payload should be rejected");
  require(binding == -1, "rejected payload must not write a binding");
}

static void test_text_field_projection(NSWindow *window) {
  extern int32_t gpui_macos_ax_test_child_count_v1(int64_t);
  id button = ax_child_with_role(window, NSAccessibilityButtonRole);
  require(button != nil, "the button should remain published");
  int64_t button_binding = ((NSObject *)button).bindingToken;
  int64_t enabled_binding = publish(window, button_binding, YES, NO, NO, 0);
  button = ax_child_with_role(window, NSAccessibilityButtonRole);
  require(button != nil, "the enabled button should remain published");
  int64_t binding = publish_field(window, 0, "hello", 2, 2, YES, YES);
  require(binding != enabled_binding, "field should use its own binding token");
  require(gpui_macos_ax_test_child_count_v1(401) == 2,
          "button and field should be exposed together");
  id field = ax_child_with_role(window, NSAccessibilityTextFieldRole);
  require(field != nil, "the view should expose one AX text field");
  require([field isAccessibilityElement], "field element should be live");
  require([[field accessibilityValue] isEqualToString:@"hello"],
          "field value should be projected");
  require([field isAccessibilityEditable], "editable should be projected");
  require([field accessibilityNumberOfCharacters] == 5,
          "field length should be projected");
  NSRange selection = [field accessibilitySelectedTextRange];
  require(selection.location == 2 && selection.length == 2,
          "UTF-16 selection should be projected");
  require([[field accessibilitySelectedText] isEqualToString:@"ll"],
          "selected text should match the range");
  require([[field accessibilityLabel] isEqualToString:@"Name"],
          "field label should be projected");
  require([[field accessibilityIdentifier]
              isEqualToString:@"gpui.mbt.macos-text-field"],
          "field identifier should be stable");
  NSRect frame = [field accessibilityFrame];
  require(fabs(frame.size.width - 240) < 1.0 &&
              fabs(frame.size.height - 32) < 1.0,
          "field AX frame should preserve logical dimensions");

  int values_before = value_notifications;
  int selections_before = selection_notifications;
  int64_t updated =
      publish_field(window, binding, "hello world", 6, 5, YES, YES);
  require(updated == binding, "updating the same field should keep its token");
  require(value_notifications == values_before + 1,
          "value change should notify once");
  require(selection_notifications == selections_before + 1,
          "selection change should notify once");
  require([field accessibilityValue] == nil ||
              [[field accessibilityValue] isEqualToString:@"hello world"],
          "field value should update in place");
  selection = [field accessibilitySelectedTextRange];
  require(selection.location == 6 && selection.length == 5,
          "updated selection should be observable");

  int focused_before = focused_element_notifications;
  publish_field(window, updated, "hello world", 6, 5, NO, YES);
  require(focused_element_notifications == focused_before + 1,
          "dropping field focus should notify once");

  int64_t ignored = 0;
  require(publish_field_raw(window, 0, "{}", &ignored) == 5,
          "existing field with a zero binding should conflict");
  require(publish_field_raw(window, updated + 1,
                            "{\"version\":1,\"role\":\"text_field\","
                            "\"label\":\"Name\",\"value\":\"x\","
                            "\"left\":20,\"top\":90,\"width\":240,"
                            "\"height\":32,\"focused\":false,"
                            "\"editable\":true,\"selection_start\":0,"
                            "\"selection_length\":0}",
                            &ignored) == 10,
          "a valid payload for a stale binding should be rejected");
  require(publish_field_raw(window, updated + 1,
                            "{\"version\":1,\"role\":\"text_field\"}",
                            &ignored) == 5,
          "invalid payload should be rejected before binding checks");

  char bytes[4096];
  make_field_payload(bytes, sizeof(bytes), "hello", 4, 2, NO, YES);
  expect_field_rejected(window, updated, bytes);
  make_field_payload(bytes, sizeof(bytes), "hello", 0, 0, YES, YES);
  bytes[strlen(bytes) - 1] = ' ';
  expect_field_rejected(window, updated, bytes);
  snprintf(bytes, sizeof(bytes),
           "{\"version\":1,\"role\":\"text_field\",\"label\":\"Name\","
           "\"value\":\"x\",\"left\":20,\"top\":90,\"width\":240,"
           "\"height\":32,\"focused\":false,\"editable\":true,"
           "\"selection_start\":0.5,\"selection_length\":0}");
  expect_field_rejected(window, updated, bytes);

  require(gpui_macos_ax_revoke_field_v1(401, updated + 1) == 10,
          "stale field binding should be rejected");
  require(gpui_macos_ax_revoke_field_v1(401, updated) == 0,
          "field revoke should succeed");
  require(gpui_macos_ax_test_child_count_v1(401) == 1,
          "field revoke should leave the button published");
  require(ax_child_with_role(window, NSAccessibilityTextFieldRole) == nil,
          "revoked field should disappear from the AX children");
  require([button accessibilityPerformPress],
          "button Invoke should still enqueue after a field revoke");
  int64_t returned = 0;
  require(gpui_macos_ax_take_request_v1(401, &returned) == 1 &&
              returned == enabled_binding,
          "button request should remain intact");
  require(gpui_macos_ax_revoke_field_v1(401, 0) == 0,
          "revoking without a field should be idempotent");
}

static void test_close_and_reopen(NSWindow *window) {
  require(gpui_macos_ax_revoke_v1(401, 0) == 0,
          "previous native test binding should be retired");
  int64_t binding = publish(window, 0, YES, NO, NO, 0);
  id stale = child(window);
  require([stale accessibilityPerformPress], "close test should queue a request");
  window.delegate = nil;
  [window close];
  require(![stale isAccessibilityElement],
          "closed window should revoke the retained native element");
  require(![stale accessibilityPerformPress],
          "closed window element should reject Invoke");
  int64_t returned = 0;
  require(gpui_macos_ax_take_request_v1(401, &returned) == 0,
          "closed window should leave no queued work");
  require(gpui_macos_ax_revoke_v1(401, binding) == 0,
          "revoking after close should be idempotent");

  NSWindow *reopened = make_window(402);
  int64_t new_binding = publish(reopened, 0, YES, NO, NO, 0);
  require(new_binding != binding,
          "reopened window should receive a distinct transport binding");
  require([child(reopened) isAccessibilityElement],
          "reopened window should expose its new live element");
  [reopened close];
}

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSWindow *window = make_window(401);
    gpui_macos_ax_test_set_notification_hook(notification_hook);
    test_integer_payload_validation(window);
    test_focus_notifications(window);
    int64_t binding = 0;
    test_projection_and_press(window, &binding);
    test_queue_capacity_and_resize(window, binding);
    test_availability_update_purges_queue(window);
    test_text_field_projection(window);
    test_close_and_reopen(window);
    puts("PASS: macOS AX projection, numeric schema, queue, revocation, and lifecycle");
  }
  return 0;
}
