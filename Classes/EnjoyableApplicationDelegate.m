//
//  EnjoyableApplicationDelegate.m
//  Enjoy
//
//  Created by Sam McCall on 4/05/09.
//

#import <Sparkle/Sparkle.h>

#import "EnjoyableApplicationDelegate.h"

#import "NJMapping.h"
#import "NJMappingsController.h"
#import "NJEvents.h"

@implementation EnjoyableApplicationDelegate {
    NSStatusItem *statusItem;
}

- (void)didSwitchApplication:(NSNotification *)note {
    NSRunningApplication *activeApp = note.userInfo[NSWorkspaceApplicationKey];
    if (activeApp)
        [self.mappingsController activateMappingForProcess:activeApp];
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    [NSNotificationCenter.defaultCenter
        addObserver:self
        selector:@selector(mappingDidChange:)
        name:NJEventMappingChanged
        object:nil];
    [NSNotificationCenter.defaultCenter
        addObserver:self
        selector:@selector(eventSimulationStarted:)
        name:NJEventSimulationStarted
        object:nil];
    [NSNotificationCenter.defaultCenter
        addObserver:self
        selector:@selector(eventSimulationStopped:)
        name:NJEventSimulationStopped
        object:nil];

    [self.mappingsController load];
    [self.mvc.mappingList reloadData];
    [self.mvc changedActiveMappingToIndex:
     [self.mappingsController indexOfMapping:
      self.mappingsController.currentMapping]];

    statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:36];
    statusItem.image = [NSImage imageNamed:@"Status Menu Icon Disabled"];
    statusItem.highlightMode = YES;
    statusItem.menu = self.statusItemMenu;
    statusItem.target = self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"hidden in status item"]
        && NSRunningApplication.currentApplication.wasLaunchedAsLoginItemOrResume)
        [self transformIntoElement:nil];
    else
        [self.window makeKeyAndOrderFront:nil];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication
                    hasVisibleWindows:(BOOL)flag {
    [self restoreToForeground:theApplication];
    return NO;
}

- (void)restoreToForeground:(id)sender {
    ProcessSerialNumber psn = { 0, kCurrentProcess };
    TransformProcessType(&psn, kProcessTransformToForegroundApplication);
    [NSApplication.sharedApplication activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:sender];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(transformIntoElement:)
                                               object:self];
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"hidden in status item"];
}

- (void)applicationWillBecomeActive:(NSNotification *)notification {
    if (self.window.isVisible)
        [self restoreToForeground:notification];
}

- (void)transformIntoElement:(id)sender {
    ProcessSerialNumber psn = { 0, kCurrentProcess };
    TransformProcessType(&psn, kProcessTransformToUIElementApplication);
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"hidden in status item"];
}

- (void)flashStatusItem {
    if ([statusItem.image.name isEqualToString:@"Status Menu Icon"]) {
        statusItem.image = [NSImage imageNamed:@"Status Menu Icon Disabled"];
    } else {
        statusItem.image = [NSImage imageNamed:@"Status Menu Icon"];
    }
    
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication {
    [theApplication hide:theApplication];
    // If we turn into a UIElement right away, the application cancels
    // the deactivation events. The dock icon disappears, but an
    // unresponsive menu bar remains until the user clicks somewhere.
    // So delay just long enough to be past the end handling that.
    [self performSelector:@selector(transformIntoElement:) withObject:self afterDelay:0.001];
    return NO;
}

- (void)eventSimulationStarted:(NSNotification *)note {
    self.simulatingEventsButton.state = NSOnState;
    statusItem.image = [NSImage imageNamed:@"Status Menu Icon"];
    [NSWorkspace.sharedWorkspace.notificationCenter
        addObserver:self
        selector:@selector(didSwitchApplication:)
        name:NSWorkspaceDidActivateApplicationNotification
        object:nil];
}

- (void)eventSimulationStopped:(NSNotification *)note {
    self.simulatingEventsButton.state = NSOffState;
    statusItem.image = [NSImage imageNamed:@"Status Menu Icon Disabled"];
    [NSWorkspace.sharedWorkspace.notificationCenter
        removeObserver:self
        name:NSWorkspaceDidActivateApplicationNotification
        object:nil];
}

- (void)mappingDidChange:(NSNotification *)note {
    NSUInteger idx = [note.userInfo[NJMappingIndexKey] intValue];
    [self.mvc changedActiveMappingToIndex:idx];

    if (!self.window.isVisible)
        for (int i = 0; i < 4; ++i)
            [self performSelector:@selector(flashStatusItem)
                       withObject:self
                       afterDelay:0.2 * i];
}

- (NSMenu *)applicationDockMenu:(NSApplication *)sender {
    return self.dockMenu;
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    [self restoreToForeground:sender];
    NSError *error;
    NSURL *URL = [NSURL fileURLWithPath:filename];
    NJMapping *mapping = [NJMapping mappingWithContentsOfURL:URL
                                                       error:&error];
    if ([self.mappingsController[mapping.name] hasConflictWith:mapping]) {
        [self promptForMapping:mapping atIndex:self.mappingsController.count];
    } else if (self.mappingsController[mapping.name]) {
        [self.mappingsController[mapping.name] mergeEntriesFrom:mapping];
    } else if (mapping) {
        [self.mvc beginUpdates];
        [self.mappingsController addMapping:mapping];
        [self.mvc addedMappingAtIndex:self.mappingsController.count - 1 startEditing:NO];
        [self.mvc endUpdates];
        [self.mappingsController activateMapping:mapping];
    } else {
        [self.window presentError:error
                   modalForWindow:self.window
                         delegate:nil
               didPresentSelector:nil
                      contextInfo:nil];
    }
    return !!mapping;
}

- (void)mappingWasChosen:(NJMapping *)mapping {
    [self.mappingsController activateMapping:mapping];
}

- (void)mappingListShouldOpen {
    [self restoreToForeground:self];
    [self.mvc mappingTriggerClicked:self];
}

- (void)loginItemPromptDidEnd:(NSWindow *)sheet
                   returnCode:(int)returnCode
                  contextInfo:(void *)contextInfo {
    if (returnCode == NSAlertDefaultReturn) {
        [NSRunningApplication.currentApplication addToLoginItems];
        // If we're going to automatically start, don't bug the user
        // about automatic updates next boot - they probably want it,
        // and if they don't they probably want a prompt for it less.
        SUUpdater.sharedUpdater.automaticallyChecksForUpdates = YES;
    }
}

- (void)loginItemPromptDidDismiss:(NSWindow *)sheet
                       returnCode:(int)returnCode
                      contextInfo:(void *)contextInfo {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"explained login items"];
    [self.window performClose:sheet];
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    if (sender != self.window
        || NSRunningApplication.currentApplication.isLoginItem
        || [NSUserDefaults.standardUserDefaults boolForKey:@"explained login items"])
        return YES;
    NSBeginAlertSheet(
        NSLocalizedString(@"login items prompt", @"alert prompt for adding to login items"),
        NSLocalizedString(@"login items add button", @"button to add to login items"),
        NSLocalizedString(@"login items don't add button", @"button to not add to login items"),
        nil, self.window, self,
        @selector(loginItemPromptDidEnd:returnCode:contextInfo:),
        @selector(loginItemPromptDidDismiss:returnCode:contextInfo:),
        NULL,
        NSLocalizedString(@"login items explanation", @"a brief explanation of login items")
        );
    for (int i = 0; i < 10; ++i)
        [self performSelector:@selector(flashStatusItem)
                   withObject:self
                   afterDelay:0.5 * i];
    return NO;
}

- (void)importMappingClicked:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedFileTypes = @[ @"enjoyable", @"json", @"txt" ];
    [panel beginSheetModalForWindow:self.window
                  completionHandler:^(NSInteger result) {
                      if (result != NSFileHandlingPanelOKButton)
                          return;
                      [panel close];
                      NSError *error;
                      NJMapping *mapping = [NJMapping mappingWithContentsOfURL:panel.URL
                                                                         error:&error];
                      if ([self.mappingsController[mapping.name] hasConflictWith:mapping]) {
                          [self promptForMapping:mapping atIndex:self.mappingsController.count];
                      } else if (self.mappingsController[mapping.name]) {
                          [self.mappingsController[mapping.name] mergeEntriesFrom:mapping];
                      } else if (mapping) {
                          [self.mappingsController addMapping:mapping];
                      } else {
                          [self.window presentError:error
                                     modalForWindow:self.window
                                           delegate:nil
                                 didPresentSelector:nil
                                        contextInfo:nil];
                      }
                  }];
    
}

- (void)exportMappingClicked:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedFileTypes = @[ @"enjoyable" ];
    NJMapping *mapping = self.mappingsController.currentMapping;
    panel.nameFieldStringValue = [mapping.name stringByFixingPathComponent];
    [panel beginSheetModalForWindow:self.window
                  completionHandler:^(NSInteger result) {
                      if (result != NSFileHandlingPanelOKButton)
                          return;
                      [panel close];
                      NSError *error;
                      if (![mapping writeToURL:panel.URL error:&error]) {
                          [self.window presentError:error
                                     modalForWindow:self.window
                                           delegate:nil
                                 didPresentSelector:nil
                                        contextInfo:nil];
                      }
                  }];
}

- (void)mappingConflictDidResolve:(NSAlert *)alert
                       returnCode:(NSInteger)returnCode
                      contextInfo:(void *)contextInfo {
    NSDictionary *userInfo = CFBridgingRelease(contextInfo);
    NJMapping *oldMapping = userInfo[@"old mapping"];
    NJMapping *newMapping = userInfo[@"new mapping"];
    NSInteger idx = [userInfo[@"index"] intValue];
    [alert.window orderOut:nil];
    switch (returnCode) {
        case NSAlertFirstButtonReturn: // Merge
            [self.mappingsController mergeMapping:newMapping intoMapping:oldMapping];
            [self.mappingsController activateMapping:oldMapping];
            break;
        case NSAlertThirdButtonReturn: // New Mapping
            [self.mvc beginUpdates];
            [self.mappingsController addMapping:newMapping];
            [self.mvc addedMappingAtIndex:idx startEditing:YES];
            [self.mvc endUpdates];
            [self.mappingsController activateMapping:newMapping];
            break;
        default: // Cancel, other.
            break;
    }
}

- (void)promptForMapping:(NJMapping *)mapping atIndex:(NSInteger)idx {
    NJMapping *mergeInto = self.mappingsController[mapping.name];
    NSAlert *conflictAlert = [[NSAlert alloc] init];
    conflictAlert.messageText = NSLocalizedString(@"import conflict prompt", @"Title of import conflict alert");
    conflictAlert.informativeText =
    [NSString stringWithFormat:NSLocalizedString(@"import conflict in %@", @"Explanation of import conflict"),
     mapping.name];
    [conflictAlert addButtonWithTitle:NSLocalizedString(@"import and merge", @"button to merge imported mappings")];
    [conflictAlert addButtonWithTitle:NSLocalizedString(@"cancel import", @"button to cancel import")];
    [conflictAlert addButtonWithTitle:NSLocalizedString(@"import new mapping", @"button to import as new mapping")];
    [conflictAlert beginSheetModalForWindow:self.window
                              modalDelegate:self
                             didEndSelector:@selector(mappingConflictDidResolve:returnCode:contextInfo:)
                                contextInfo:(void *)CFBridgingRetain(@{ @"index": @(idx),
                                                                        @"old mapping": mergeInto,
                                                                        @"new mapping": mapping })];
}

- (NSInteger)numberOfMappings:(NJMappingsViewController *)mvc {
    return self.mappingsController.count;
}

- (NJMapping *)mappingsViewController:(NJMappingsViewController *)mvc
                      mappingForIndex:(NSUInteger)idx {
    return self.mappingsController[idx];
}

- (void)mappingsViewController:(NJMappingsViewController *)mvc
          renameMappingAtIndex:(NSInteger)index
                        toName:(NSString *)name {
    [self.mappingsController renameMapping:self.mappingsController[index]
                                        to:name];
}

- (BOOL)mappingsViewController:(NJMappingsViewController *)mvc
       canMoveMappingFromIndex:(NSInteger)fromIdx
                       toIndex:(NSInteger)toIdx {
    return fromIdx != toIdx && fromIdx != 0 && toIdx != 0
            && toIdx < (NSInteger)self.mappingsController.count;
}

- (void)mappingsViewController:(NJMappingsViewController *)mvc
          moveMappingFromIndex:(NSInteger)fromIdx
                       toIndex:(NSInteger)toIdx {
    [mvc beginUpdates];
    [mvc.mappingList moveRowAtIndex:fromIdx toIndex:toIdx];
    [self.mappingsController moveMoveMappingFromIndex:fromIdx toIndex:toIdx];
    [mvc endUpdates];
}

- (BOOL)mappingsViewController:(NJMappingsViewController *)mvc
       canRemoveMappingAtIndex:(NSInteger)idx {
    return idx != 0;
}

- (void)mappingsViewController:(NJMappingsViewController *)mvc
          removeMappingAtIndex:(NSInteger)idx {
    [mvc beginUpdates];
    [mvc removedMappingAtIndex:idx];
    [self.mappingsController removeMappingAtIndex:idx];
    [mvc endUpdates];
}

- (BOOL)mappingsViewController:(NJMappingsViewController *)mvc
          importMappingFromURL:(NSURL *)url
                       atIndex:(NSInteger)index
                         error:(NSError **)error {
    NJMapping *mapping = [NJMapping mappingWithContentsOfURL:url
                                                       error:error];
    if ([self.mappingsController[mapping.name] hasConflictWith:mapping]) {
        [self promptForMapping:mapping atIndex:index];
    } else if (self.mappingsController[mapping.name]) {
        [self.mappingsController[mapping.name] mergeEntriesFrom:mapping];
    } else if (mapping) {
        [self.mvc beginUpdates];
        [self.mvc addedMappingAtIndex:index startEditing:NO];
        [self.mappingsController insertMapping:mapping atIndex:index];
        [self.mvc endUpdates];
    }
    return !!mapping;
}

- (void)mappingsViewController:(NJMappingsViewController *)mvc
                    addMapping:(NJMapping *)mapping {
    [mvc beginUpdates];
    [mvc addedMappingAtIndex:self.mappingsController.count startEditing:YES];
    [self.mappingsController addMapping:mapping];
    [mvc endUpdates];
    [self.mappingsController activateMapping:mapping];
}

- (void)mappingsViewController:(NJMappingsViewController *)mvc
           choseMappingAtIndex:(NSInteger)idx {
    [self.mappingsController activateMapping:self.mappingsController[idx]];
}

- (id)deviceViewController:(NJDeviceViewController *)dvc
             elementForUID:(NSString *)uid {
    return self.deviceController[uid];
}

- (void)deviceViewControllerDidSelectNothing:(NJDeviceViewController *)dvc {
    [self.outputController loadInput:dvc.selectedHandler];
}

- (void)deviceViewController:(NJDeviceViewController *)dvc
             didSelectBranch:(NJInputPathElement *)handler {
    [self.outputController loadInput:dvc.selectedHandler];
}

- (void)deviceViewController:(NJDeviceViewController *)dvc
            didSelectHandler:(NJInputPathElement *)handler {
    [self.outputController loadInput:dvc.selectedHandler];
}

- (void)deviceViewController:(NJDeviceViewController *)dvc
             didSelectDevice:(NJInputPathElement *)device {
    [self.outputController loadInput:dvc.selectedHandler];
}

- (void)deviceController:(NJDeviceController *)dc
            didAddDevice:(NJDevice *)device {
    [self.dvc addedDevice:device atIndex:dc.count - 1];
}

- (void)deviceController:(NJDeviceController *)dc
  didRemoveDeviceAtIndex:(NSInteger)idx {
    [self.dvc removedDeviceAtIndex:idx];
}

- (void)deviceControllerDidStartHID:(NJDeviceController *)dc {
    [self.dvc hidStarted];
}

- (void)deviceControllerDidStopHID:(NJDeviceController *)dc {
    [self.dvc hidStopped];
}

- (void)deviceController:(NJDeviceController *)dc didInput:(NJInput *)input {
    [self.outputController loadInput:input];
    [self.outputController focusKey];
}

- (void)deviceController:(NJDeviceController *)dc didError:(NSError *)error {
    // Since the error shows the window, it can trigger another attempt
    // to re-open the HID manager, which will also probably fail and error,
    // so don't bother repeating ourselves.
    if (!self.window.attachedSheet) {
        [NSApplication.sharedApplication activateIgnoringOtherApps:YES];
        [self.window makeKeyAndOrderFront:nil];
        [self.window presentError:error
                   modalForWindow:self.window
                         delegate:nil
               didPresentSelector:nil
                      contextInfo:nil];
    }
}

- (NSInteger)numberOfDevicesInDeviceList:(NJDeviceViewController *)dvc {
    return self.deviceController.count;
}

- (NJDevice *)deviceViewController:(NJDeviceViewController *)dvc
                    deviceForIndex:(NSUInteger)idx {
    return self.deviceController[idx];
}

- (IBAction)simulatingEventsChanged:(NSButton *)sender {
    self.deviceController.simulatingEvents = sender.state == NSOnState;
}

@end
