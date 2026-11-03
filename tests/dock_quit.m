/*
 * dock_quit — an application that has just quit is not on the strip, and its dot is dark.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * **THE DOCK'S REFRESH IS DRIVEN BY `NSWorkspace`'s NOTIFICATIONS, AND THAT CLASS POSTS `DidTerminate` BEFORE IT DROPS THE
 * APPLICATION FROM `-runningApplications`.** Deliberate, so a handler can still read what went — and fatal to a Dock that
 * simply refreshes in that callback, because the list it reads still names the quitter: the strip kept an unpinned tile
 * and a pinned one kept its lit dot. MEASURED as "quitting an app doesn't always make it disappear from the dock if it's
 * unpinned, nor make the indicator light go out if it's pinned".
 *
 * WHAT THIS PROBE CAN MEASURE WITHOUT A SCREEN is the rule the refresh applies to that list: the terminating application is
 * taken out by identifier, everybody else is left alone, and no identifier means "nothing to take out". The controller is
 * made with `-init`, so no window, strip or defaults are touched.
 */
#import "DockController.h"

#import <AppKit/NSRunningApplication.h>
#import <AppKit/NSWorkspace.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static int s_failed;

static void check(int condition, const char *message)
{
	printf("%s %s\n", condition ? "  ok  " : "  FAIL", message);
	if (!condition) {
		s_failed++;
	}
}

int main(void)
{
	@autoreleasepool {
		NSRunningApplication *desktop =
			[[[NSRunningApplication alloc] cg_initWithBundleIdentifier:@"org.agora.desktop"] autorelease];
		NSRunningApplication *editor =
			[[[NSRunningApplication alloc] cg_initWithBundleIdentifier:@"org.agora.editor"] autorelease];
		NSArray *running = [NSArray arrayWithObjects:desktop, editor, nil];
		NSArray *after;
		DockTile *tile;

		/* 1. THE QUITTER IS TAKEN OUT, AND ONLY THE QUITTER. */
		after = [DockController applicationsForRefresh:running excluding:editor];
		check([after count] == 1, "a refresh for a quit application draws from one fewer application");
		check([[after objectAtIndex:0] bundleIdentifier] != nil
		      && [[[after objectAtIndex:0] bundleIdentifier] isEqualToString:@"org.agora.desktop"],
		      "and the one left is the one that did not quit");

		/* 2. NOTHING TO TAKE OUT IS THE LIST ITSELF — a launch and an activation refresh with the list as it is. */
		check([[DockController applicationsForRefresh:running excluding:nil] count] == 2,
		      "a refresh with no terminating application keeps them all");

		/* AND A CLIENT THAT NAMES NO BUNDLE IS DROPPED BY IDENTITY, because a name is exactly what it has not got. */
		{
			NSRunningApplication *anonymous =
				[[[NSRunningApplication alloc] cg_initWithBundleIdentifier:nil] autorelease];
			NSArray *withAnonymous = [NSArray arrayWithObjects:desktop, anonymous, nil];

			check([[DockController applicationsForRefresh:withAnonymous excluding:anonymous] count] == 1,
			      "an anonymous client that quits is taken out too, by identity rather than by name");
		}

		/* 3. AND A TILE WITH NO APPLICATION BEHIND IT IS NOT RUNNING: the dot the strip draws. */
		tile = [DockTile tileWithApplication:editor];
		check(tile != nil && [tile isRunning], "a tile made from a running application is lit");
		[tile setApplication:nil];
		check(![tile isRunning], "and the same tile with no application behind it is dark");

		/* 4. THE DOOR THE TERMINATE HANDLER CALLS IS THE ONE THE CONTROLLER HAS, not a second path. */
		check([[[DockController alloc] init] respondsToSelector:@selector(refreshExcluding:)],
		      "the controller refreshes with an exclusion, which is what the terminate notification uses");
	}
	printf(s_failed == 0 ? "dock_quit: all checks passed\n" : "dock_quit: FAILURES\n");
	return s_failed == 0 ? 0 : 1;
}
