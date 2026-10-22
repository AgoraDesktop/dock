/*
 * DockController.m — the strip, the tiles, and what a click means.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * **THE WINDOW'S FRAME IS THE STRIP AND THE RESERVATION IS THE SAME NUMBER.** `DockStripRect` says where the strip
 * is — flush with the side, ending at the menu bar — and `-cg_setReservedEdge:amount:` tells the window server that
 * the same width is furniture, so `NSScreen -visibleFrame` shrinks by it and no maximised window runs under the
 * Dock. Two statements of one number, made together, which is why they live in one method.
 *
 * **AND IT NEVER TAKES THE KEYBOARD.** Two halves, both stated: the Accessory activation policy (so the Dock has no
 * menu bar of its own) and `-cg_setActivatable:NO` on the window (`agora_window.set_activatable`), so a click on a
 * tile reaches the Dock's view without making the Dock the active application. Without the second half the menu bar
 * followed the click and the desktop was left with no bar at all — MEASURED, and the reason the door exists.
 */
#import "DockController.h"

#import "DockView.h"

#import <AppKit/NSApplication.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSDockMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSRunningApplication.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSStatusBar.h>
#import <AppKit/NSWorkspace.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSString.h>
#import <Foundation/NSUserDefaults.h>

#include <stdio.h>
#include <stdlib.h>

@implementation DockController

- (id)initWithOrientation:(DockOrientation)orientation
{
	if ((self = [super init]) != nil) {
		NSScreen *screen = [NSScreen mainScreen];
		NSRect screenFrame = [screen frame];
		CGFloat menuBar = [[NSStatusBar systemStatusBar] thickness];
		NSRect strip;

		_orientation = orientation;
		_metrics = DockDefaultMetrics;
		_applications = [[NSArray alloc] init];
		if (screenFrame.size.width <= 0.0 || screenFrame.size.height <= 0.0) {
			fprintf(stderr, "dock: no screen to sit on\n");
			[self release];
			return nil;
		}
		if (menuBar <= 0.0) {
			menuBar = 24.0;	/* a compositor that does not answer: the bar's own height, once */
		}
		strip = DockStripRect(screenFrame, menuBar, _orientation, _metrics);

		_window = [[NSWindow alloc] initWithContentRect:strip
						      styleMask:NSBorderlessWindowMask
							backing:NSBackingStoreBuffered
							  defer:NO];
		/* **TRANSPARENT, AND SAID BEFORE THE WINDOW IS SHOWN.** The seam chooses the buffer's format from
		 * `-isOpaque` when the window is made, so this order is the difference between a translucent band and a
		 * black rectangle. */
		[_window setOpaque:NO];
		[_window setBackgroundColor:[NSColor clearColor]];
		[_window setLevel:NSDockWindowLevel];
		[_window setReleasedWhenClosed:NO];
		/* NOT IN THE WINDOW MENU, NOT IN EXPOSÉ, AND NOT MOVED BY EITHER: the Dock is furniture. */
		[_window setCollectionBehavior:(NSWindowCollectionBehaviorStationary | NSWindowCollectionBehaviorIgnoresCycle)];
		/* **AND A CLICK ON IT NEVER MAKES THE DOCK THE ACTIVE APPLICATION.** Without this, clicking a tile gives
		 * the DOCK the keyboard, the menu bar follows it, and the desktop is left with no bar at all — MEASURED,
		 * which is why the door exists. The pointer still reaches the Dock; only the keyboard and the bar stay put. */
		[_window cg_setActivatable:NO];

		_view = [[DockView alloc] initWithFrame:NSMakeRect(0.0, 0.0, strip.size.width, strip.size.height)];
		[_view setOrientation:_orientation];
		[_view setController:self];
		[_window setContentView:_view];
		[_window orderFront:nil];

		/* **AND THE SCREEN IS TOLD THE STRIP IS TAKEN.** This is `agora_window.set_reserved` through the AppKit's
		 * Agora-owned door: right-edge furniture reserves the right edge, left-edge furniture the left, and every
		 * application's `-visibleFrame` shrinks by it from here on. */
		[_window cg_setReservedEdge:(_orientation == DockOrientationRight ? NSMaxXEdge : NSMinXEdge)
				     amount:_metrics.width];

		[[NSNotificationCenter defaultCenter] addObserver:self
							 selector:@selector(applicationsChanged:)
							     name:NSWorkspaceDidLaunchApplicationNotification
							   object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self
							 selector:@selector(applicationsChanged:)
							     name:NSWorkspaceDidTerminateApplicationNotification
							   object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self
							 selector:@selector(applicationsChanged:)
							     name:NSWorkspaceDidActivateApplicationNotification
							   object:nil];
		[self refresh];
		/* **THE LINE DOES NOT COUNT APPLICATIONS, BECAUSE AT THIS MOMENT THERE CANNOT BE ANY.** The list is a
		 * Wayland snapshot: `-runningApplications` asks for it, and the answer arrives on a later loop pass, so a
		 * count read here is always zero however many applications are running — MEASURED as `0 application(s)` in
		 * a session where Workspace was on the screen, which reads as a bug and is only the ask preceding the
		 * answer. The real count is a snapshot's to report; `AGORA_DOCK_DIAG=1` prints it after every one. */
		fprintf(stderr, "dock: %s, strip %.0fx%.0f at (%.0f,%.0f)\n",
			_orientation == DockOrientationRight ? "right" : "left",
			(double)strip.size.width, (double)strip.size.height, (double)strip.origin.x,
			(double)strip.origin.y);
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_applications release];
	[_menuApplication release];
	[_view release];
	[_window release];
	[super dealloc];
}

- (DockOrientation)orientation
{
	return _orientation;
}

- (NSRect)stripRect
{
	return [_window frame];
}

/* ---------------------------------------------------------------------------------------------------
 * the model
 * --------------------------------------------------------------------------------------------------- */

/* **THE DOCK IS NOT IN ITS OWN LIST.** Its window declares the Dock's bundle identifier like any application's, so
 * the workspace reports it; a Dock that drew a tile for itself would be a tile that does nothing. The filter is by
 * identifier and not by object, because a relaunch makes a new object with the same name. */
- (NSArray *)applicationsExcludingSelf:(NSArray *)all
{
	NSMutableArray *kept = [NSMutableArray array];
	NSString *selfIdentifier = [[NSBundle mainBundle] bundleIdentifier];
	NSUInteger i;

	for (i = 0; i < [all count]; i++) {
		NSRunningApplication *application = [all objectAtIndex:i];

		if (selfIdentifier != nil && [[application bundleIdentifier] isEqualToString:selfIdentifier]) {
			continue;
		}
		[kept addObject:application];
	}
	return kept;
}

- (void)refresh
{
	NSArray *all = [[NSWorkspace sharedWorkspace] runningApplications];
	NSArray *kept = [self applicationsExcludingSelf:all];
	NSRunningApplication *frontmost = [[NSWorkspace sharedWorkspace] frontmostApplication];

	[kept retain];
	[_applications release];
	_applications = kept;
	[_view setApplications:_applications];
	[_view setActiveApplication:(frontmost != nil && [_applications containsObject:frontmost]) ? frontmost : nil];
	/* **A TRACE, BECAUSE A DOCK IS HARD TO LOOK AT FROM A TEST.** `AGORA_DOCK_DIAG=1` prints what the strip
	 * believes after every snapshot — the same shape the AppKit's own `APPKIT_*_DIAG` switches have, and what
	 * `demo/` and a bug report are read from. */
	if (getenv("AGORA_DOCK_DIAG") != NULL) {
		NSUInteger i;

		fprintf(stderr, "dock: %lu application(s)", (unsigned long)[_applications count]);
		for (i = 0; i < [_applications count]; i++) {
			NSRunningApplication *application = [_applications objectAtIndex:i];

			fprintf(stderr, " %s%s", [[application bundleIdentifier] UTF8String],
				[application isActive] ? "*" : "");
		}
		fprintf(stderr, "\n");
	}
}

- (void)applicationsChanged:(id)notification
{
	(void)notification;
	[self refresh];
}

/* ---------------------------------------------------------------------------------------------------
 * what a click means
 * --------------------------------------------------------------------------------------------------- */

- (void)activateTileAtIndex:(NSNumber *)index
{
	NSUInteger i = (NSUInteger)[index integerValue];

	if (i >= [_applications count]) {
		return;
	}
	/* **A CLICK ON A TILE IS `-activateWithOptions:`, WHICH IS RAISE AND KEYBOARD — OR A REQUEST FOR A WINDOW.**
	 * The application's windows come forward — all of them, in the order they were already in — and the frontmost
	 * takes the keyboard, which is what makes the menu bar change to the application the person just picked. An
	 * application whose windows are all furniture (Workspace with its desktop and no file window) has nothing to
	 * raise, and then the AppKit asks it to reopen and it opens a window. The Dock does not decide which of the two
	 * happened: a tile names an application, and what "bring it forward" means is the application's answer. */
	[[_applications objectAtIndex:i] activateWithOptions:NSApplicationActivateAllWindows];
}

- (void)showMenuForTileAtIndex:(NSNumber *)index withEvent:(id)event
{
	NSUInteger i = (NSUInteger)[index integerValue];
	NSRunningApplication *application;
	NSMenu *menu;
	NSMenuItem *item;
	NSString *title;

	if (i >= [_applications count]) {
		return;
	}
	application = [_applications objectAtIndex:i];
	[_menuApplication release];
	_menuApplication = [application retain];

	/* **THE APPLICATION'S OWN ITEMS COME FIRST, AND THEY COME FROM IT.** A tile's menu is the application's answer to
	 * `-applicationDockMenu:` with the Dock's own rows under it — the Mac's arrangement, and the reason the two
	 * halves have to meet in ONE panel: an application cannot draw at the Dock's edge, and a Dock cannot know what an
	 * application's menu means. `NSDockMenu` asks (bounded), waits, and builds the rows; each carries the id the
	 * application gave it, which is what a pick sends back. */
	menu = [[NSDockMenu menuForApplication:application] retain];
	if (menu == nil) {
		/* NO MENU IS STILL A MENU: the Dock's own rows, and nothing else. */
		menu = [[NSMenu alloc] initWithTitle:@""];
	} else {
		[self bindApplicationItemsInMenu:menu];
		/* **AND THE DOCK DOES NOT RE-VALIDATE THE APPLICATION'S ROWS.** `-update`'s enabling walk would ask each
		 * item's target — which is this controller now — whether it answers the action, and that would enable
		 * every row the description marked disabled. The validation was made in the application, where the real
		 * targets are, so the Dock's job is to draw what it was told. */
		[menu setAutoenablesItems:NO];
		/* A SEPARATOR ONLY WHEN THERE IS SOMETHING ABOVE IT TO SEPARATE — an empty application menu followed by a
		 * rule would be a menu that starts with one. */
		if ([menu numberOfItems] > 0) {
			[menu addItem:[NSMenuItem separatorItem]];
		}
	}

	title = [NSString stringWithFormat:@"Quit %@", [application localizedName]];
	item = [[NSMenuItem alloc] initWithTitle:title action:@selector(quitFromMenu:) keyEquivalent:@""];
	[item setTarget:self];
	[menu addItem:item];
	[item release];
	[NSMenu popUpContextMenu:menu withEvent:event forView:_view];
	[menu release];
}

/* **THE APPLICATION'S ROWS BECOME THE DOCK'S TO SEND, AND NOTHING ELSE ABOUT THEM CHANGES.** A row the description
 * gave an id is one the person may choose, so it gets this controller and one selector — the id travels in its
 * `-representedObject` — while a row that opens a submenu is recursed into and the submenu's own rows are bound the
 * same way. Separators and anything without an id are left exactly as they arrived. */
- (void)bindApplicationItemsInMenu:(NSMenu *)menu
{
	NSArray *items = [menu itemArray];
	NSUInteger i;

	for (i = 0; i < [items count]; i++) {
		NSMenuItem *menuItem = [items objectAtIndex:i];

		if ([menuItem submenu] != nil) {
			[self bindApplicationItemsInMenu:(NSMenu *)[menuItem submenu]];
			continue;
		}
		if ([menuItem representedObject] == nil) {
			continue;
		}
		[menuItem setTarget:self];
		[menuItem setAction:@selector(activateApplicationMenuItem:)];
	}
}

- (void)activateApplicationMenuItem:(id)sender
{
	NSNumber *identifier = [(NSMenuItem *)sender representedObject];

	if (_menuApplication == nil || identifier == nil) {
		return;
	}
	/* **THE ID AND THE APPLICATION, AND NOTHING ELSE CROSSES.** What the row means — the action, the target, the
	 * state it changes — is the application's, and it sends it itself when the id comes home. */
	[NSDockMenu dispatchActionForItem:[identifier integerValue] toApplication:_menuApplication];
}

- (void)quitFromMenu:(id)sender
{
	(void)sender;
	/* **A REQUEST, NOT A KILL.** `-terminate` asks every window to close and the application decides; Force Quit
	 * is the session's, and there is no session yet. */
	[_menuApplication terminate];
}

@end
