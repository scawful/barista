#import "BaristaTabRegistry.h"

#import "HomeTabViewController.h"
#import "AppearanceTabViewController.h"
#import "WidgetsTabViewController.h"
#import "SpacesTabViewController.h"
#import "IconsTabViewController.h"
#import "MenuTabViewController.h"
#import "ThemesTabViewController.h"
#import "ShortcutsTabViewController.h"
#import "IntegrationsTabViewController.h"
#import "LaunchAgentsTabViewController.h"
#import "DebugTabViewController.h"
#import "PerformanceTabViewController.h"
#import "AdvancedTabViewController.h"

@implementation BaristaTabRegistry

+ (NSArray<NSDictionary *> *)defaultTabDescriptors {
  static NSArray<NSDictionary *> *descriptors = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    descriptors = @[
      @{ @"id": @"home", @"label": @"Home", @"icon": @"󰋗", @"section": @"Overview", @"controllerClass": [HomeTabViewController class] },
      @{ @"id": @"appearance", @"label": @"Appearance", @"icon": @"󰛨", @"section": @"Bar", @"controllerClass": [AppearanceTabViewController class] },
      @{ @"id": @"widgets", @"label": @"Widgets", @"icon": @"󰀻", @"section": @"Bar", @"controllerClass": [WidgetsTabViewController class] },
      @{ @"id": @"spaces", @"label": @"Spaces", @"icon": @"󰍉", @"section": @"Bar", @"controllerClass": [SpacesTabViewController class] },
      @{ @"id": @"icons", @"label": @"Icons", @"icon": @"󰞅", @"section": @"Bar", @"controllerClass": [IconsTabViewController class] },
      @{ @"id": @"themes", @"label": @"Themes", @"icon": @"󰸌", @"section": @"Bar", @"controllerClass": [ThemesTabViewController class] },
      @{ @"id": @"menu", @"label": @"Menu", @"icon": @"󰍜", @"section": @"Menu", @"controllerClass": [MenuTabViewController class] },
      @{ @"id": @"shortcuts", @"label": @"Shortcuts", @"icon": @"󰌌", @"section": @"Menu", @"controllerClass": [ShortcutsTabViewController class] },
      @{ @"id": @"integrations", @"label": @"Integrations", @"icon": @"󰐱", @"section": @"System", @"controllerClass": [IntegrationsTabViewController class] },
      @{ @"id": @"launchAgents", @"label": @"Launch Agents", @"icon": @"󰑓", @"section": @"System", @"controllerClass": [LaunchAgentsTabViewController class] },
      @{ @"id": @"performance", @"label": @"Performance", @"icon": @"󱎫", @"section": @"System", @"controllerClass": [PerformanceTabViewController class] },
      @{ @"id": @"debug", @"label": @"Debug", @"icon": @"󰃤", @"section": @"System", @"controllerClass": [DebugTabViewController class] },
      @{ @"id": @"advanced", @"label": @"Advanced", @"icon": @"󰒓", @"section": @"Advanced", @"controllerClass": [AdvancedTabViewController class] },
    ];
  });
  return descriptors;
}

+ (NSDictionary *)descriptorForIdentifier:(NSString *)identifier {
  if (!identifier.length) {
    return nil;
  }

  for (NSDictionary *descriptor in [self defaultTabDescriptors]) {
    NSString *candidate = descriptor[@"id"];
    if ([candidate isEqualToString:identifier]) {
      return descriptor;
    }
  }
  return nil;
}

@end
