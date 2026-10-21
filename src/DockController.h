/*
 * DockController.h — the Dock's application: the strip, its tiles, and what a click means.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * **THE DOCK IS A CLIENT, AND THIS IS THE CLIENT.** It owns one borderless window at `NSDockWindowLevel`, it asks
 * the server for a reserved strip so maximised windows do not run under it (`-cg_setReservedEdge:amount:`), and it
 * draws the application it can see: the running applications from `NSWorkspace`, one tile each.
 *
 * **WHERE IT SITS IS A DECISION AND NOT A DEFAULT.** Agora's Dock is VERTICAL and on the RIGHT by default — never
 * along the bottom, and never overlapping the menu bar, which is the server's strip and sits above it at level 24.
 * Left is the alternative, chosen with `DockOrientation` in the defaults or `AGORA_DOCK_POSITION` in the
 * environment; the layout is a mirror and nothing else changes.
 */
#ifndef DOCK_CONTROLLER_H
#define DOCK_CONTROLLER_H

#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>
#import <AppKit/NSWindow.h>

#import "DockLayout.h"

@class NSArray;
@class NSRunningApplication;
@class NSWindow;
@class DockView;

@interface DockController : NSObject
{
@private
	NSWindow *_window;
	DockView *_view;
	NSArray *_applications;		/* NSRunningApplication, without this application itself */
	NSRunningApplication *_menuApplication;
	DockOrientation _orientation;
	DockMetrics _metrics;
}

/* `orientation` is what the Dock was started with; the caller decides it from the defaults and the environment. */
- (id)initWithOrientation:(DockOrientation)orientation;

- (DockOrientation)orientation;
/* The strip the Dock has taken, in screen coordinates — the number a test or a log is about. */
- (NSRect)stripRect;

/* The two doors the view calls, and the menu's own action. */
- (void)activateTileAtIndex:(NSNumber *)index;
- (void)showMenuForTileAtIndex:(NSNumber *)index withEvent:(id)event;
- (void)quitFromMenu:(id)sender;

@end

#endif /* DOCK_CONTROLLER_H */
