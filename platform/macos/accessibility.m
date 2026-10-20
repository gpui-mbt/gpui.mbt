#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#include <float.h>
#include <math.h>
#include <stdint.h>
#include <string.h>
#include "accessibility_abi.h"

/*
 * Narrow AppKit projection for macOS Button and TextField accessibility. The
 * only values crossing this boundary are copied attributes and opaque,
 * revocable binding tokens. MoonBit NodeIds and callbacks never enter this
 * file.
 *
 * A window owns a small registry keyed by binding token. Each element reads its
 * attributes from that registry rather than from a single associated child, so
 * one window can publish a Button and a TextField at the same time.
 */
#define GPUI_AX_QUEUE_CAPACITY 64
#define GPUI_AX_PAYLOAD_LIMIT 65536
#define GPUI_AX_FIELD_VALUE_LIMIT 16384

enum {
  GPUIAX_ROLE_BUTTON = 1,
  GPUIAX_ROLE_TEXT_FIELD = 2,
};

@interface GPWindow : NSObject
@property int64_t token;
@end

@interface GPView : NSView
@end

@class GPUIAXElement;

static char gpui_ax_registry_key;
static int64_t gpui_ax_next_binding_token;
static NSMutableArray<NSDictionary *> *gpui_ax_pending_requests;
static id gpui_ax_close_observer;
static id gpui_ax_resize_observer;

#ifdef GPUI_TESTING
typedef void (*GPUIAXNotificationHook)(id, NSAccessibilityNotificationName);
static GPUIAXNotificationHook gpui_ax_notification_hook;

void gpui_macos_ax_test_set_notification_hook(GPUIAXNotificationHook hook) {
  gpui_ax_notification_hook = hook;
}
#endif

static void gpui_ax_post_notification(
    id element, NSAccessibilityNotificationName notification) {
#ifdef GPUI_TESTING
  if (gpui_ax_notification_hook)
    gpui_ax_notification_hook(element, notification);
#endif
  NSAccessibilityPostNotification(element, notification);
}

static id gpui_ax_focus_fallback(NSView *view, GPUIAXElement *excluded,
                                 GPUIAXElement *previous) {
  id focused = [NSApp accessibilityApplicationFocusedUIElement];
  if (focused && focused != excluded && focused != previous) return focused;
  id ancestor = NSAccessibilityUnignoredAncestor(view);
  return ancestor ?: view;
}

@interface GPUIAXElement : NSAccessibilityElement
@property(nonatomic, weak) NSWindow *ownerWindow;
@property(nonatomic, weak) NSView *ownerView;
@property(nonatomic, copy) NSString *label;
@property(nonatomic, copy) NSString *help;
@property(nonatomic) NSRect logicalFrame;
@property(nonatomic) int64_t windowToken;
@property(nonatomic) int64_t bindingToken;
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL loading;
@property(nonatomic) BOOL focused;
@property(nonatomic) BOOL revoked;
- (BOOL)isLive;
- (NSInteger)axRole;
- (void)revoke;
@end

@interface GPUIAXButtonElement : GPUIAXElement
@end

@interface GPUIAXTextFieldElement : GPUIAXElement
@property(nonatomic, copy) NSString *value;
@property(nonatomic) BOOL editable;
@property(nonatomic) NSRange selectedRange;
@end

static NSMutableDictionary<NSNumber *, GPUIAXElement *> *gpui_ax_registry(
    NSView *view, BOOL create) {
  if (!view) return nil;
  NSMutableDictionary *registry =
      objc_getAssociatedObject(view, &gpui_ax_registry_key);
  if (!registry && create) {
    registry = [NSMutableDictionary new];
    objc_setAssociatedObject(view, &gpui_ax_registry_key, registry,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  }
  return registry;
}

static GPUIAXElement *gpui_ax_lookup(NSView *view, int64_t binding_token) {
  if (!view || binding_token <= 0) return nil;
  return gpui_ax_registry(view, NO)[@(binding_token)];
}

static GPUIAXElement *gpui_ax_role_element(NSView *view, NSInteger role) {
  NSMutableDictionary *registry = gpui_ax_registry(view, NO);
  for (GPUIAXElement *element in registry.allValues) {
    if (element.axRole == role && !element.revoked) return element;
  }
  return nil;
}

static NSArray<GPUIAXElement *> *gpui_ax_live_elements(NSView *view) {
  NSMutableArray *elements = [NSMutableArray array];
  NSMutableDictionary *registry = gpui_ax_registry(view, NO);
  NSArray<NSNumber *> *keys =
      [registry.allKeys sortedArrayUsingSelector:@selector(compare:)];
  for (NSNumber *key in keys) {
    GPUIAXElement *element = registry[key];
    if (element && [element isLive]) [elements addObject:element];
  }
  return elements;
}

@implementation GPView (GPUIAXChildren)
- (NSArray *)accessibilityChildren {
  return gpui_ax_live_elements(self);
}
@end

static int64_t gpui_ax_window_token(NSWindow *window) {
  id delegate = window.delegate;
  if (!delegate ||
      ![NSStringFromClass([delegate class]) isEqualToString:@"GPWindow"] ||
      ![delegate respondsToSelector:@selector(token)])
    return 0;
  int64_t (*read_token)(id, SEL) =
      (int64_t (*)(id, SEL))[delegate methodForSelector:@selector(token)];
  return read_token ? read_token(delegate, @selector(token)) : 0;
}

static NSWindow *gpui_ax_find_window(int64_t token) {
  if (token <= 0 || !NSApp) return nil;
  for (NSWindow *window in NSApp.windows) {
    if (gpui_ax_window_token(window) == token && window.contentView)
      return window;
  }
  return nil;
}

static void gpui_ax_remove_requests(int64_t window_token, int64_t binding_token) {
  if (!gpui_ax_pending_requests) return;
  NSIndexSet *indexes = [gpui_ax_pending_requests indexesOfObjectsPassingTest:
      ^BOOL(NSDictionary *request, NSUInteger index, BOOL *stop) {
        (void)index;
        (void)stop;
        return [request[@"window"] longLongValue] == window_token &&
            (binding_token == 0 ||
             [request[@"binding"] longLongValue] == binding_token);
      }];
  [gpui_ax_pending_requests removeObjectsAtIndexes:indexes];
}

/* Drop an element from the registry without posting layout notifications. */
static void gpui_ax_forget_element(NSView *view, GPUIAXElement *element) {
  if (!element) return;
  int64_t binding_token = element.bindingToken;
  [element revoke];
  NSMutableDictionary *registry = gpui_ax_registry(view, NO);
  if (registry[@(binding_token)] == element)
    [registry removeObjectForKey:@(binding_token)];
  gpui_ax_remove_requests(element.windowToken, binding_token);
}

/* Revoke an element and report the layout/focus change to AppKit. */
static void gpui_ax_remove_element(NSView *view, GPUIAXElement *element) {
  if (!element) return;
  BOOL was_focused = element.focused;
  gpui_ax_forget_element(view, element);
  gpui_ax_post_notification(view,
                            NSAccessibilityLayoutChangedNotification);
  if (was_focused)
    gpui_ax_post_notification(
        gpui_ax_focus_fallback(view, element, nil),
        NSAccessibilityFocusedUIElementChangedNotification);
}

static void gpui_ax_remove_all(NSView *view, int64_t window_token) {
  NSMutableDictionary *registry = gpui_ax_registry(view, NO);
  for (GPUIAXElement *element in registry.allValues)
    gpui_ax_forget_element(view, element);
  [registry removeAllObjects];
  gpui_ax_remove_requests(window_token, 0);
  gpui_ax_post_notification(view,
                            NSAccessibilityLayoutChangedNotification);
}

static void gpui_ax_install_observers(void) {
  if (!gpui_ax_close_observer) {
    gpui_ax_close_observer =
        [NSNotificationCenter.defaultCenter
            addObserverForName:NSWindowWillCloseNotification
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *note) {
                      NSWindow *window = note.object;
                      int64_t token = gpui_ax_window_token(window);
                      if (token <= 0) {
                        NSArray *elements =
                            gpui_ax_live_elements(window.contentView);
                        if (elements.count > 0)
                          token = ((GPUIAXElement *)elements[0]).windowToken;
                      }
                      if (token > 0)
                        gpui_ax_remove_all(window.contentView, token);
                    }];
  }
  if (!gpui_ax_resize_observer) {
    gpui_ax_resize_observer =
        [NSNotificationCenter.defaultCenter
            addObserverForName:NSWindowDidResizeNotification
                        object:nil
                         queue:nil
            usingBlock:^(NSNotification *note) {
                      NSWindow *window = note.object;
                      int64_t token = gpui_ax_window_token(window);
                      /* The frame is computed from the live view/window.
                       * Drop accepted work at resize; the MoonBit owner
                       * revokes the binding if its semantic generation or
                       * bounds changed while consuming the resize event. */
                      if (token > 0) gpui_ax_remove_requests(token, 0);
                    }];
  }
}

@implementation GPUIAXElement
- (BOOL)isLive {
  if (self.revoked || !self.ownerWindow || !self.ownerView ||
      self.ownerView.window != self.ownerWindow ||
      gpui_ax_find_window(self.windowToken) != self.ownerWindow)
    return NO;
  return gpui_ax_lookup(self.ownerView, self.bindingToken) == self;
}

- (NSInteger)axRole {
  return 0;
}

- (BOOL)isAccessibilityElement { return [self isLive]; }

- (NSAccessibilityRole)accessibilityRole { return nil; }

- (NSString *)accessibilityLabel {
  return [self isLive] ? self.label : nil;
}

- (NSString *)accessibilityTitle {
  return [self isLive] ? self.label : nil;
}

- (NSRect)accessibilityFrame {
  if (![self isLive] || !self.ownerWindow.isVisible) return NSZeroRect;
  NSView *view = self.ownerView;
  NSRect bounds = view.bounds;
  if (!NSContainsRect(bounds, self.logicalFrame)) return NSZeroRect;
  NSRect in_window = [view convertRect:self.logicalFrame toView:nil];
  return [self.ownerWindow convertRectToScreen:in_window];
}

- (id)accessibilityParent { return [self isLive] ? self.ownerView : nil; }

- (id)accessibilityTopLevelUIElement {
  return [self isLive] ? self.ownerWindow : nil;
}

- (id)accessibilityWindow { return [self isLive] ? self.ownerWindow : nil; }

- (NSPoint)accessibilityActivationPoint {
  NSRect frame = [self accessibilityFrame];
  return NSIsEmptyRect(frame) ? NSZeroPoint
                              : NSMakePoint(NSMidX(frame), NSMidY(frame));
}

- (BOOL)isAccessibilityFocused { return [self isLive] && self.focused; }

- (BOOL)isAccessibilityEnabled { return [self isLive] && self.enabled; }

- (NSString *)accessibilityHelp { return [self isLive] ? self.help : nil; }

- (void)revoke {
  self.revoked = YES;
  self.label = nil;
  self.help = nil;
  self.ownerWindow = nil;
  self.ownerView = nil;
}
@end

@implementation GPUIAXButtonElement
- (NSInteger)axRole {
  return GPUIAX_ROLE_BUTTON;
}

- (NSAccessibilityRole)accessibilityRole {
  return [self isLive] ? NSAccessibilityButtonRole : nil;
}

- (NSString *)accessibilityIdentifier {
  return [self isLive] ? @"gpui.mbt.macos-button.run-action" : nil;
}

- (BOOL)accessibilityPerformPress {
  if (![NSThread isMainThread] || ![self isLive] ||
      !self.ownerWindow.isVisible || !self.enabled ||
      self.loading || self.bindingToken <= 0)
    return NO;
  if (!gpui_ax_pending_requests)
    gpui_ax_pending_requests = [NSMutableArray new];
  if (gpui_ax_pending_requests.count >= GPUI_AX_QUEUE_CAPACITY) return NO;
  [gpui_ax_pending_requests addObject:@{
    @"window" : @(self.windowToken),
    @"binding" : @(self.bindingToken),
  }];
  return YES;
}
@end

@implementation GPUIAXTextFieldElement
- (NSInteger)axRole {
  return GPUIAX_ROLE_TEXT_FIELD;
}

- (NSAccessibilityRole)accessibilityRole {
  return [self isLive] ? NSAccessibilityTextFieldRole : nil;
}

- (NSString *)accessibilityIdentifier {
  return [self isLive] ? @"gpui.mbt.macos-text-field" : nil;
}

- (id)accessibilityValue {
  return [self isLive] ? self.value : nil;
}

- (BOOL)isAccessibilityEditable {
  return [self isLive] && self.editable;
}

- (NSRange)accessibilitySelectedTextRange {
  return [self isLive] ? self.selectedRange : NSMakeRange(NSNotFound, 0);
}

- (NSInteger)accessibilityNumberOfCharacters {
  return [self isLive] ? (NSInteger)self.value.length : 0;
}

- (NSString *)accessibilitySelectedText {
  if (![self isLive] || self.selectedRange.location == NSNotFound ||
      self.selectedRange.location + self.selectedRange.length >
          self.value.length)
    return nil;
  return [self.value substringWithRange:self.selectedRange];
}

- (NSString *)accessibilityStringForRange:(NSRange)range {
  if (![self isLive] || range.location == NSNotFound ||
      range.location + range.length > self.value.length)
    return nil;
  return [self.value substringWithRange:range];
}

- (NSRange)accessibilityVisibleCharacterRange {
  if (![self isLive]) return NSMakeRange(NSNotFound, 0);
  return NSMakeRange(0, self.value.length);
}
@end

static BOOL gpui_ax_boolean(NSDictionary *dictionary, NSString *key,
                            BOOL *value) {
  id candidate = dictionary[key];
  if (![candidate isKindOfClass:NSNumber.class] ||
      CFGetTypeID((__bridge CFTypeRef)candidate) != CFBooleanGetTypeID())
    return NO;
  *value = [candidate boolValue];
  return YES;
}

static BOOL gpui_ax_number(NSDictionary *dictionary, NSString *key,
                          double *value) {
  id candidate = dictionary[key];
  if (![candidate isKindOfClass:NSNumber.class] ||
      CFGetTypeID((__bridge CFTypeRef)candidate) == CFBooleanGetTypeID())
    return NO;
  double number = [candidate doubleValue];
  if (!isfinite(number)) return NO;
  *value = number;
  return YES;
}

static BOOL gpui_ax_integer(NSDictionary *dictionary, NSString *key,
                            double minimum, double maximum, int64_t *value) {
  id candidate = dictionary[key];
  if (![candidate isKindOfClass:NSNumber.class] ||
      CFGetTypeID((__bridge CFTypeRef)candidate) == CFBooleanGetTypeID() ||
      CFGetTypeID((__bridge CFTypeRef)candidate) != CFNumberGetTypeID() ||
      CFNumberIsFloatType((__bridge CFNumberRef)candidate))
    return NO;
  double number = [candidate doubleValue];
  if (!isfinite(number) || trunc(number) != number ||
      number < minimum || number > maximum)
    return NO;
  if (value) *value = (int64_t)number;
  return YES;
}

static NSDictionary *gpui_ax_json(const uint8_t *bytes, int32_t length) {
  if (!bytes || length <= 0 || length > GPUI_AX_PAYLOAD_LIMIT) return nil;
  NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)length];
  NSError *error = nil;
  id value = [NSJSONSerialization JSONObjectWithData:data
                                             options:NSJSONReadingFragmentsAllowed
                                               error:&error];
  if (error || ![value isKindOfClass:NSDictionary.class]) return nil;
  return value;
}

static BOOL gpui_ax_frame(NSDictionary *dictionary, NSRect *frame) {
  double left = 0, top = 0, width = 0, height = 0;
  if (!gpui_ax_number(dictionary, @"left", &left) ||
      !gpui_ax_number(dictionary, @"top", &top) ||
      !gpui_ax_number(dictionary, @"width", &width) ||
      !gpui_ax_number(dictionary, @"height", &height) ||
      left < 0 || top < 0 || width <= 0 || height <= 0 || left > 8192 ||
      top > 8192 || width > 8192 || height > 8192 || left + width > 8192 ||
      top + height > 8192)
    return NO;
  *frame = NSMakeRect(left, top, width, height);
  return YES;
}

static NSDictionary *gpui_ax_decode_payload(const uint8_t *bytes,
                                            int32_t length) {
  NSDictionary *dictionary = gpui_ax_json(bytes, length);
  if (!dictionary) return nil;
  NSSet *expected = [NSSet setWithArray:@[
    @"version", @"role", @"name", @"left", @"top", @"width", @"height",
    @"enabled", @"loading", @"focused", @"activations", @"actions",
  ]];
  if (![[NSSet setWithArray:dictionary.allKeys] isEqualToSet:expected])
    return nil;
  int64_t version = 0, activations = 0;
  NSString *role = dictionary[@"role"];
  NSString *name = dictionary[@"name"];
  NSArray *actions = dictionary[@"actions"];
  if (!gpui_ax_integer(dictionary, @"version", 1, 1, &version) ||
      version != 1 || ![role isKindOfClass:NSString.class] ||
      ![role isEqualToString:@"button"] ||
      ![name isKindOfClass:NSString.class] || name.length > 4096 ||
      !gpui_ax_integer(dictionary, @"activations", 0, INT32_MAX,
                       &activations) ||
      ![actions isKindOfClass:NSArray.class] || actions.count != 1 ||
      ![actions[0] isKindOfClass:NSString.class] ||
      ![actions[0] isEqualToString:@"Invoke"])
    return nil;
  NSRect frame = NSZeroRect;
  BOOL enabled = NO, loading = NO, focused = NO;
  if (!gpui_ax_frame(dictionary, &frame) ||
      !gpui_ax_boolean(dictionary, @"enabled", &enabled) ||
      !gpui_ax_boolean(dictionary, @"loading", &loading) ||
      !gpui_ax_boolean(dictionary, @"focused", &focused) ||
      (focused && !enabled))
    return nil;
  return dictionary;
}

static NSDictionary *gpui_ax_decode_field_payload(const uint8_t *bytes,
                                                  int32_t length) {
  NSDictionary *dictionary = gpui_ax_json(bytes, length);
  if (!dictionary) return nil;
  NSSet *expected = [NSSet setWithArray:@[
    @"version", @"role", @"label", @"value", @"left", @"top", @"width",
    @"height", @"focused", @"editable", @"selection_start",
    @"selection_length",
  ]];
  if (![[NSSet setWithArray:dictionary.allKeys] isEqualToSet:expected])
    return nil;
  int64_t version = 0, selection_start = 0, selection_length = 0;
  NSString *role = dictionary[@"role"];
  NSString *label = dictionary[@"label"];
  NSString *value = dictionary[@"value"];
  NSRect frame = NSZeroRect;
  BOOL focused = NO, editable = NO;
  if (!gpui_ax_integer(dictionary, @"version", 1, 1, &version) ||
      version != 1 || ![role isKindOfClass:NSString.class] ||
      ![role isEqualToString:@"text_field"] ||
      ![label isKindOfClass:NSString.class] || label.length > 4096 ||
      ![value isKindOfClass:NSString.class] ||
      value.length > GPUI_AX_FIELD_VALUE_LIMIT ||
      !gpui_ax_frame(dictionary, &frame) ||
      !gpui_ax_boolean(dictionary, @"focused", &focused) ||
      !gpui_ax_boolean(dictionary, @"editable", &editable) ||
      !gpui_ax_integer(dictionary, @"selection_start", 0,
                       (double)value.length, &selection_start) ||
      !gpui_ax_integer(dictionary, @"selection_length", 0,
                       (double)value.length, &selection_length) ||
      selection_start + selection_length > (int64_t)value.length)
    return nil;
  return dictionary;
}

static GPUIAXElement *gpui_ax_create_element(NSWindow *window, GPView *view,
                                             NSInteger role,
                                             int64_t window_token,
                                             int64_t *error) {
  if (gpui_ax_next_binding_token == INT64_MAX) {
    *error = 13;
    return nil;
  }
  GPUIAXElement *element =
      role == GPUIAX_ROLE_TEXT_FIELD
          ? (GPUIAXElement *)[GPUIAXTextFieldElement new]
          : (GPUIAXElement *)[GPUIAXButtonElement new];
  element.windowToken = window_token;
  element.bindingToken = ++gpui_ax_next_binding_token;
  element.ownerWindow = window;
  element.ownerView = view;
  gpui_ax_registry(view, YES)[@(element.bindingToken)] = element;
  return element;
}

/* Returns 0 on success. The input is a copied, versioned UTF-8 JSON payload. */
int32_t gpui_macos_ax_publish_v1(int64_t window_token,
                                 int64_t existing_binding_token,
                                 const uint8_t *bytes, int32_t length,
                                 int64_t *out_binding_token) {
  if (![NSThread isMainThread]) return 18;
  if (!out_binding_token || existing_binding_token < 0) return 5;
  @autoreleasepool {
    NSWindow *window = gpui_ax_find_window(window_token);
    if (!window || !window.contentView) return 10;
    NSDictionary *payload = gpui_ax_decode_payload(bytes, length);
    if (!payload) return 5;
    GPView *view = (GPView *)window.contentView;
    GPUIAXButtonElement *current =
        (GPUIAXButtonElement *)gpui_ax_role_element(view, GPUIAX_ROLE_BUTTON);
    GPUIAXButtonElement *previous = current;
    BOOL previous_focused = previous && previous.focused;

    if (existing_binding_token != 0 && current &&
        current.bindingToken != existing_binding_token)
      return 10;
    if (existing_binding_token == 0 && current) return 12;
    BOOL enabled = [payload[@"enabled"] boolValue];
    BOOL loading = [payload[@"loading"] boolValue];
    BOOL focused = [payload[@"focused"] boolValue];
    double left = [payload[@"left"] doubleValue];
    double top = [payload[@"top"] doubleValue];
    double width = [payload[@"width"] doubleValue];
    double height = [payload[@"height"] doubleValue];
    NSString *name = payload[@"name"];
    int64_t activations = [payload[@"activations"] longLongValue];
    NSString *help = [NSString stringWithFormat:
        @"Activations: %lld; %@; %@", activations,
        enabled ? @"Enabled" : @"Disabled", loading ? @"Loading" : @"Ready"];

    if (current && ((current.enabled != enabled) ||
                    (current.loading != loading) ||
                    !NSEqualRects(current.logicalFrame,
                                  NSMakeRect(left, top, width, height)))) {
      gpui_ax_forget_element(view, current);
      current = nil;
    }

    BOOL created = NO;
    if (!current) {
      int64_t failure = 0;
      current = (GPUIAXButtonElement *)gpui_ax_create_element(
          window, view, GPUIAX_ROLE_BUTTON, window_token, &failure);
      if (!current) return (int32_t)failure;
      created = YES;
    }
    current.label = name;
    current.help = help;
    current.logicalFrame = NSMakeRect(left, top, width, height);
    current.enabled = enabled;
    current.loading = loading;
    current.focused = focused;
    current.revoked = NO;
    *out_binding_token = current.bindingToken;
    gpui_ax_install_observers();
    BOOL focused_element_changed =
        (previous_focused != focused) || (previous_focused && previous != current);
    if (created)
      gpui_ax_post_notification(view,
                                NSAccessibilityLayoutChangedNotification);
    else
      gpui_ax_post_notification(current,
                                NSAccessibilityValueChangedNotification);
    if (focused_element_changed)
      gpui_ax_post_notification(
          focused ? current : gpui_ax_focus_fallback(view, current, previous),
          NSAccessibilityFocusedUIElementChangedNotification);
    return 0;
  }
}

int32_t gpui_macos_ax_publish_field_v1(int64_t window_token,
                                       int64_t existing_binding_token,
                                       const uint8_t *bytes, int32_t length,
                                       int64_t *out_binding_token) {
  if (![NSThread isMainThread]) return 18;
  if (!out_binding_token || existing_binding_token < 0) return 5;
  @autoreleasepool {
    NSWindow *window = gpui_ax_find_window(window_token);
    if (!window || !window.contentView) return 10;
    NSDictionary *payload = gpui_ax_decode_field_payload(bytes, length);
    if (!payload) return 5;
    GPView *view = (GPView *)window.contentView;
    GPUIAXTextFieldElement *current = (GPUIAXTextFieldElement *)
        gpui_ax_role_element(view, GPUIAX_ROLE_TEXT_FIELD);
    GPUIAXTextFieldElement *previous = current;
    BOOL previous_focused = previous && previous.focused;
    NSRange previous_selection =
        previous ? previous.selectedRange : NSMakeRange(NSNotFound, 0);

    if (existing_binding_token != 0 && current &&
        current.bindingToken != existing_binding_token)
      return 10;
    if (existing_binding_token == 0 && current) return 12;
    double left = [payload[@"left"] doubleValue];
    double top = [payload[@"top"] doubleValue];
    double width = [payload[@"width"] doubleValue];
    double height = [payload[@"height"] doubleValue];
    NSRect frame = NSMakeRect(left, top, width, height);
    BOOL focused = [payload[@"focused"] boolValue];
    BOOL editable = [payload[@"editable"] boolValue];
    NSString *label = payload[@"label"];
    NSString *value = payload[@"value"];
    NSRange selection = NSMakeRange(
        (NSUInteger)[payload[@"selection_start"] longLongValue],
        (NSUInteger)[payload[@"selection_length"] longLongValue]);
    if (current &&
        (!NSEqualRects(current.logicalFrame, frame) ||
         current.editable != editable)) {
      gpui_ax_forget_element(view, current);
      current = nil;
    }
    BOOL created = NO;
    if (!current) {
      int64_t failure = 0;
      current = (GPUIAXTextFieldElement *)gpui_ax_create_element(
          window, view, GPUIAX_ROLE_TEXT_FIELD, window_token, &failure);
      if (!current) return (int32_t)failure;
      created = YES;
    }
    current.label = label;
    current.value = value;
    current.selectedRange = selection;
    current.logicalFrame = frame;
    current.editable = editable;
    current.focused = focused;
    current.revoked = NO;
    *out_binding_token = current.bindingToken;
    gpui_ax_install_observers();
    BOOL focused_element_changed =
        (previous_focused != focused) || (previous_focused && previous != current);
    if (created) {
      gpui_ax_post_notification(view,
                                NSAccessibilityLayoutChangedNotification);
    } else {
      gpui_ax_post_notification(
          current, NSAccessibilityValueChangedNotification);
      if (!NSEqualRanges(previous_selection, selection))
        gpui_ax_post_notification(
            current, NSAccessibilitySelectedTextChangedNotification);
    }
    if (focused_element_changed)
      gpui_ax_post_notification(
          focused ? current : gpui_ax_focus_fallback(view, current, previous),
          NSAccessibilityFocusedUIElementChangedNotification);
    return 0;
  }
}

int32_t gpui_macos_ax_revoke_v1(int64_t window_token,
                                int64_t binding_token) {
  if (![NSThread isMainThread]) return 18;
  if (binding_token < 0) return 5;
  @autoreleasepool {
    NSWindow *window = gpui_ax_find_window(window_token);
    if (!window) {
      gpui_ax_remove_requests(window_token, 0);
      return 0;
    }
    GPUIAXElement *current =
        gpui_ax_role_element(window.contentView, GPUIAX_ROLE_BUTTON);
    if (!current) {
      gpui_ax_remove_requests(window_token, 0);
      return 0;
    }
    if (binding_token != 0 && current.bindingToken != binding_token) return 10;
    gpui_ax_remove_element(window.contentView, current);
    return 0;
  }
}

int32_t gpui_macos_ax_revoke_field_v1(int64_t window_token,
                                      int64_t binding_token) {
  if (![NSThread isMainThread]) return 18;
  if (binding_token < 0) return 5;
  @autoreleasepool {
    NSWindow *window = gpui_ax_find_window(window_token);
    if (!window) return 0;
    GPUIAXElement *current =
        gpui_ax_role_element(window.contentView, GPUIAX_ROLE_TEXT_FIELD);
    if (!current) return 0;
    if (binding_token != 0 && current.bindingToken != binding_token) return 10;
    gpui_ax_remove_element(window.contentView, current);
    return 0;
  }
}

/* Returns 0 for no request, 1 for one live request, or an ErrorCode ordinal. */
int32_t gpui_macos_ax_take_request_v1(int64_t window_token,
                                     int64_t *out_binding_token) {
  if (![NSThread isMainThread]) return 18;
  if (!out_binding_token) return 5;
  @autoreleasepool {
    *out_binding_token = 0;
    if (!gpui_ax_pending_requests) return 0;
    NSWindow *window = gpui_ax_find_window(window_token);
    for (NSUInteger index = 0; index < gpui_ax_pending_requests.count;) {
      NSDictionary *request = gpui_ax_pending_requests[index];
      int64_t request_window = [request[@"window"] longLongValue];
      if (request_window != window_token) {
        /* Closed windows are pruned even if the owner no longer polls them. */
        if (!gpui_ax_find_window(request_window)) {
          [gpui_ax_pending_requests removeObjectAtIndex:index];
          continue;
        }
        index += 1;
        continue;
      }
      int64_t binding = [request[@"binding"] longLongValue];
      [gpui_ax_pending_requests removeObjectAtIndex:index];
      GPUIAXElement *current = window
          ? gpui_ax_lookup(window.contentView, binding)
          : nil;
      if (!window || !current || current.axRole != GPUIAX_ROLE_BUTTON ||
          current.bindingToken != binding || !current.enabled ||
          current.loading)
        continue;
      *out_binding_token = binding;
      return 1;
    }
    return 0;
  }
}

#ifdef GPUI_TESTING
int32_t gpui_macos_ax_test_press_v1(int64_t window_token) {
  if (![NSThread isMainThread]) return 18;
  NSWindow *window = gpui_ax_find_window(window_token);
  if (!window) return 10;
  GPUIAXElement *element =
      gpui_ax_role_element(window.contentView, GPUIAX_ROLE_BUTTON);
  return element && [(GPUIAXButtonElement *)element accessibilityPerformPress]
      ? 0
      : 12;
}

int32_t gpui_macos_ax_test_child_count_v1(int64_t window_token) {
  if (![NSThread isMainThread]) return -18;
  NSWindow *window = gpui_ax_find_window(window_token);
  if (!window) return -10;
  return (int32_t)gpui_ax_live_elements(window.contentView).count;
}
#endif
