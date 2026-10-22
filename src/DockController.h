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
@class NSMenu;
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

/* The two doors the view calls, and the menu's own actions. */
- (void)activateTileAtIndex:(NSNumber *)index;
- (void)showMenuForTileAtIndex:(NSNumber *)index withEvent:(id)event;
/* **AND THE BINDING WALK**, which gives each of the application's rows the Dock's own target so that a pick can be
 * routed back by the id the application gave it. Recursive over submenus; declared here because the menu builder
 * calls it before it is defined. */
- (void)bindApplicationItemsInMenu:(NSMenu *)menu;
- (void)quitFromMenu:(id)sender;
/* **AND THE ROW THAT CAME FROM THE APPLICATION.** A tile's menu is composed of two halves — the items the
 * application published for that tile and the Dock's own under them — and a row of the first half is dispatched by
 * its id, back to the application that numbered it. The Dock never sees an action, a target or a meaning. */
- (void)activateApplicationMenuItem:(id)sender;

@end

#endif /* DOCK_CONTROLLER_H */
