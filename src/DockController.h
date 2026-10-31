/*
 * DockController.h — the Dock's application: the strip, its tiles, and what a click, a menu or a drag means.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * **THE DOCK IS A CLIENT, AND THIS IS THE CLIENT.** It owns one borderless window at `NSDockWindowLevel`, it asks
 * the server for a reserved strip so maximised windows do not run under it (`-cg_setReservedEdge:amount:`), and it
 * draws the tiles it can see: the PINNED applications in their saved order, then the running ones nobody pinned.
 *
 * **WHERE IT SITS IS A DECISION AND NOT A DEFAULT.** Agora's Dock is VERTICAL and on the RIGHT by default — never
 * along the bottom, and never overlapping the menu bar, which is the server's strip and sits above it at level 24.
 * Left is the alternative, chosen with `DockOrientation` in the defaults or `AGORA_DOCK_POSITION` in the
 * environment; the layout is a mirror and nothing else changes.
 *
 * **AND THE DESKTOP IS NOT ONE OF THE TILES A PERSON ARRANGES.** Workspace's tile is always present, always first and
 * cannot be removed (`DockOrder` enforces all three); its menu offers no pin row and no Quit, but a RESTART — the
 * desktop is what everything else is drawn over, and a desktop that has wedged is repaired by replacing it, not by
 * ending it.
 *
 * **AND THE PINNED LIST IS THE DOCK'S OWN PREFERENCE**, written under `DockPinnedApplications` in the Dock's OWN
 * defaults domain (`-initWithSuiteName:` with this application's identifier — not the tier's standard defaults, which
 * today answer the global domain until the app domain follows the bundle): one dictionary per pin (identifier, title,
 * path), which is what lets a pinned tile outlive its application. `DockOrder` does the list arithmetic; this class
 * owns the tiles, the window and the writing.
 */
#ifndef DOCK_CONTROLLER_H
#define DOCK_CONTROLLER_H

#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>
#import <AppKit/NSWindow.h>

#import "DockLayout.h"

@class NSArray;
@class NSMenu;
@class NSMutableArray;
@class NSRunningApplication;
@class NSUserDefaults;
@class NSWindow;
@class DockTile;
@class DockView;

@interface DockController : NSObject
{
@private
	NSWindow *_window;
	DockView *_view;
	NSArray *_tiles;		/* DockTile, in the order the strip is showing */
	NSMutableArray *_pinned;	/* DockTile, in the user's order: the place each one keeps whether or not it runs */
	DockTile *_menuTile;		/* the tile the open menu belongs to, retained for its rows' sake */
	NSString *_draggingIdentifier;	/* what a drag is moving, and therefore what it pins when it is let go */
	NSArray *_orderBeforeDrag;	/* the order a cancelled drag goes back to */
	NSUserDefaults *_defaults;	/* THIS application's domain: where the pinned list is written */
	NSWindow *_catcher;		/* the invisible window a tile's menu puts up so a dismiss-click is not a click */
	BOOL _restartPending;		/* the desktop was asked to quit so that it can be started again */
	DockOrientation _orientation;
	DockMetrics _metrics;
}

/* `orientation` is what the Dock was started with; the caller decides it from the defaults and the environment. */
- (id)initWithOrientation:(DockOrientation)orientation;

- (DockOrientation)orientation;
/* The strip the Dock has taken, in screen coordinates — the number a test or a log is about. */
- (NSRect)stripRect;

/* The doors the view calls. */
- (void)activateTileAtIndex:(NSNumber *)index;
- (void)showMenuForTileAtIndex:(NSNumber *)index withEvent:(id)event;

/* **THE DRAG, IN THREE DOORS, BECAUSE A DRAG IS THREE MOMENTS.** `-move…` is one step of a live drag (the tile
 * follows the pointer, nothing is written down); `-commitTileOrder` is the release that PINS the tile where it was
 * dropped and writes the order to the defaults; `-cancelTileOrder` puts back the order the drag started from, for a
 * release that never arrived or a press that interrupted one. */
/* **AND A DRAG FROM ANOTHER APPLICATION PINS AT THE SLOT IT WAS DROPPED ON.** The paths are application bundles (the view
 * has already filtered what it will accept, and this filters again through the same constructor, so the door is safe to
 * call from anywhere); the slot is a position in the displayed strip, and a negative one means the end — a drop past the
 * last tile. Answers YES when at least one application was pinned. */
- (BOOL)pinApplicationPaths:(NSArray *)paths atIndex:(NSInteger)index;

- (void)moveTileFromIndex:(NSNumber *)from toIndex:(NSNumber *)to;
- (void)commitTileOrder;
- (void)cancelTileOrder;

/* **AND THE BINDING WALK**, which gives each of the application's rows the Dock's own target so that a pick can be
 * routed back by the id the application gave it. Recursive over submenus; declared here because the menu builder
 * calls it before it is defined. */
- (void)bindApplicationItemsInMenu:(NSMenu *)menu;
/* The menu's own rows: this tile's pin, the application's Quit, and the DESKTOP's restart — the one row that is not
 * about the tile's place on the strip but about the application the strip is furniture for. */
- (void)togglePinFromMenu:(id)sender;
- (void)quitFromMenu:(id)sender;
- (void)restartFromMenu:(id)sender;
/* **AND THE ROW THAT CAME FROM THE APPLICATION.** A tile's menu is composed of two halves — the items the
 * application published for that tile and the Dock's own under them — and a row of the first half is dispatched by
 * its id, back to the application that numbered it. The Dock never sees an action, a target or a meaning. */
- (void)activateApplicationMenuItem:(id)sender;

@end

#endif /* DOCK_CONTROLLER_H */
