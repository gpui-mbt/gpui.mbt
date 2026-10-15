// Exercises the actual policy helper without creating NSApplication, windows,
// GPU devices, input, or permission prompts. These are safety branch tests.
#import "../platform/macos/native.m"

@interface PolicyFixture : NSObject
@property NSInteger observedPolicy;
@property NSInteger resultingPolicy;
@property BOOL setterResult;
@property NSUInteger requests;
@property NSUInteger reads;
@property BOOL changeAfterFirstRead;
- (NSApplicationActivationPolicy)activationPolicy;
- (BOOL)setActivationPolicy:(NSApplicationActivationPolicy)policy;
@end
@implementation PolicyFixture
- (NSApplicationActivationPolicy)activationPolicy {
  self.reads++;
  return self.changeAfterFirstRead && self.reads > 1 ? self.resultingPolicy : self.observedPolicy;
}
- (BOOL)setActivationPolicy:(NSApplicationActivationPolicy)policy {
  NSCAssert(policy == NSApplicationActivationPolicyAccessory, @"Only accessory requested");
  self.requests++;
  self.observedPolicy = self.resultingPolicy;
  return self.setterResult;
}
@end

static void check(NSInteger before, BOOL setter, NSInteger after, BOOL expected, NSUInteger requests) {
  PolicyFixture *fixture = [PolicyFixture new];
  fixture.observedPolicy = before;
  fixture.setterResult = setter;
  fixture.resultingPolicy = after;
  NSCAssert(ensure_background_policy((NSApplication *)fixture) == expected, @"Policy acceptance differs");
  NSCAssert(fixture.requests == requests, @"Unexpected policy transition request");
}

int main(void) {
  @autoreleasepool {
    check(NSApplicationActivationPolicyAccessory, NO, NSApplicationActivationPolicyAccessory, YES, 0);
    check(NSApplicationActivationPolicyProhibited, YES, NSApplicationActivationPolicyAccessory, YES, 1);
    check(NSApplicationActivationPolicyRegular, NO, NSApplicationActivationPolicyRegular, NO, 1);
    check(NSApplicationActivationPolicyProhibited, YES, NSApplicationActivationPolicyProhibited, NO, 1);
    check(NSApplicationActivationPolicyRegular, NO, NSApplicationActivationPolicyAccessory, NO, 1);
    PolicyFixture *unstable = [PolicyFixture new];
    unstable.observedPolicy = NSApplicationActivationPolicyAccessory;
    unstable.resultingPolicy = NSApplicationActivationPolicyRegular;
    unstable.changeAfterFirstRead = YES;
    NSCAssert(!ensure_background_policy((NSApplication *)unstable), @"Final observed policy must remain Accessory");
    NSCAssert(unstable.requests == 0, @"Existing Accessory must not request a transition");
    puts("6 background policy safety cases passed; no native application launched");
  }
  return 0;
}
