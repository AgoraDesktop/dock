/*
 * main.m — the Dock's entry point: the strip, its model, and the loop.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 *   Dock [--position right|left] [--seconds N]
 *
 * **`--position` IS THE SAME CHOICE THE DEFAULTS STORE HOLDS**, so a session script can set it for one run without
 * writing a preference a person would then have to find and undo: the environment (`AGORA_DOCK_POSITION`), then the
 * flag, then `DockOrientation` in the defaults, then right.
 *
 * `--seconds` is a TEST'S door, the same one Workspace's entry point has, and is named as one: a Dock is a thing
 * that stays, and a suite needs it to be able to leave.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSRunningApplication.h>

#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSString.h>
#import <Foundation/NSUserDefaults.h>

#import "DockController.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static DockOrientation orientationFromName(NSString *name, int *known)
{
	if (known != NULL) {
		*known = 1;
	}
	if (name == nil) {
		return DockOrientationRight;
	}
	if ([name caseInsensitiveCompare:@"left"] == 0) {
		return DockOrientationLeft;
	}
	if ([name caseInsensitiveCompare:@"right"] == 0) {
		return DockOrientationRight;
	}
	if (known != NULL) {
		*known = 0;
	}
	return DockOrientationRight;
}

int main(int argc, char **argv)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSApplication *application;
	DockController *dock;
	NSString *position = nil;
	double seconds = 0.0;
	int i;

	/* THE FLAG FIRST, because it is the most specific thing the caller said. */
	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--position") == 0 && i + 1 < argc) {
			position = [NSString stringWithUTF8String:argv[++i]];
		} else if (strcmp(argv[i], "--seconds") == 0 && i + 1 < argc) {
			seconds = atof(argv[++i]);
		} else {
			fprintf(stderr, "usage: %s [--position right|left] [--seconds N]\n", argv[0]);
			[pool release];
			return 2;
		}
	}
	if (position == nil) {
		const char *environment = getenv("AGORA_DOCK_POSITION");

		if (environment != NULL) {
			position = [NSString stringWithUTF8String:environment];
		}
	}
	if (position == nil) {
		position = [[NSUserDefaults standardUserDefaults] stringForKey:@"DockOrientation"];
	}

	application = [NSApplication sharedApplication];
	/* **ACCESSORY, BECAUSE THE DOCK HAS NO MENUS OF ITS OWN.** An application with the Regular policy owns the menu
	 * bar when it is active; the Dock must never be the application the bar belongs to. The policy is the AppKit's
	 * half and `-cg_setActivatable:` on the window is the window server's — a policy alone would not stop a click
	 * from taking the keyboard, which is why the Strip's controller sets both. */
	[application setActivationPolicy:NSApplicationActivationPolicyAccessory];
	[application finishLaunching];

	dock = [[DockController alloc] initWithOrientation:orientationFromName(position, NULL)];
	if (dock == nil) {
		fprintf(stderr, "dock: could not create the strip\n");
		[pool release];
		return 1;
	}

	if (seconds > 0.0) {
		/* A TEST'S LOOP: pump until the deadline, then leave. The events have to travel through NSApplication so
		 * that the workspace's snapshots arrive the way they will in a session. */
		NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];

		while ([deadline timeIntervalSinceNow] > 0.0) {
			NSEvent *event = [application nextEventMatchingMask:NSAnyEventMask
								  untilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]
								     inMode:nil
								    dequeue:YES];

			if (event != nil) {
				[application sendEvent:event];
			}
		}
	} else {
		[application run];
	}

	[dock release];
	[pool release];
	return 0;
}
