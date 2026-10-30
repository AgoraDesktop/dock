/*
 * DockOrder.m — the four list questions a Dock asks, answered without a window.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * Every door here returns a NEW autoreleased array and reads its inputs only. The controller keeps the result (it
 * owns the tile list) and the pinned list is written back to the defaults from it, so there is one place where the
 * Dock's shape is computed and no second copy of the rules.
 */
#import "DockOrder.h"

#import <Foundation/NSArray.h>

NSString *const DockDesktopIdentifier = @"io.github.agoradesktop.workspace";

/* **THE DESKTOP GOES TO THE TOP, AND THAT IS APPLIED BY EVERY DOOR BELOW.** One helper rather than a rule each of them
 * remembers: an array that names the desktop anywhere (or twice) comes back with ONE copy of it at index 0 and the
 * rest in their order. */
static void fn_desktop_first(NSMutableArray *identifiers)
{
	NSUInteger i;
	BOOL found = NO;

	/* ONE COPY: a list that names the desktop twice is a list with a mistake in it, not two tiles. */
	for (i = 0; i < [identifiers count]; ) {
		if ([[identifiers objectAtIndex:i] isEqualToString:DockDesktopIdentifier]) {
			if (found) {
				[identifiers removeObjectAtIndex:i];
				continue;
			}
			found = YES;
		}
		i++;
	}
	if (!found) {
		return;
	}
	for (i = 0; i < [identifiers count]; i++) {
		if ([[identifiers objectAtIndex:i] isEqualToString:DockDesktopIdentifier]) {
			break;
		}
	}
	if (i > 0 && i < [identifiers count]) {
		id desktop = [[identifiers objectAtIndex:i] retain];

		[identifiers removeObjectAtIndex:i];
		[identifiers insertObject:desktop atIndex:0];
		[desktop release];
	}
}

/* AN IDENTIFIER IS THE DOCK'S NAME FOR AN APPLICATION: `-[NSRunningApplication bundleIdentifier]`, which the window
 * list carries, so the tiles and the pinned list name the same thing. A nil or empty one is skipped rather than
 * stored: a tile that cannot be named cannot be pinned, clicked twice or matched to its own application. */
static BOOL fn_usable_identifier(id identifier)
{
	return [identifier isKindOfClass:[NSString class]] && [(NSString *)identifier length] > 0;
}

NSArray *DockOrderIdentifiers(NSArray *pinnedIdentifiers, NSArray *runningIdentifiers)
{
	NSMutableArray *order = [NSMutableArray array];
	NSUInteger i;

	for (i = 0; i < [pinnedIdentifiers count]; i++) {
		id identifier = [pinnedIdentifiers objectAtIndex:i];

		if (fn_usable_identifier(identifier) && ![order containsObject:identifier]) {
			[order addObject:identifier];
		}
	}
	for (i = 0; i < [runningIdentifiers count]; i++) {
		id identifier = [runningIdentifiers objectAtIndex:i];

		if (fn_usable_identifier(identifier) && ![order containsObject:identifier]) {
			[order addObject:identifier];
		}
	}
	fn_desktop_first(order);
	return order;
}

NSArray *DockOrderMoving(NSArray *items, NSUInteger from, NSUInteger to)
{
	NSMutableArray *moved = [NSMutableArray arrayWithArray:items];
	id item;

	if (moved == nil || from >= [moved count]) {
		return moved;
	}
	item = [[moved objectAtIndex:from] retain];
	[moved removeObjectAtIndex:from];
	if (to > [moved count]) {
		to = [moved count];	/* a drop past the last tile is the last position */
	}
	[moved insertObject:item atIndex:to];
	[item release];
	return moved;
}

NSArray *DockOrderPinnedAfterMove(NSArray *pinnedIdentifiers, NSArray *displayedIdentifiers, NSString *dragged)
{
	NSMutableArray *pinned = [NSMutableArray array];
	NSUInteger i;

	for (i = 0; i < [displayedIdentifiers count]; i++) {
		id identifier = [displayedIdentifiers objectAtIndex:i];

		if (!fn_usable_identifier(identifier)) {
			continue;
		}
		if ((dragged != nil && [identifier isEqualToString:dragged]) ||
		    [pinnedIdentifiers containsObject:identifier]) {
			[pinned addObject:identifier];
		}
	}
	/* A DRAG NEVER UNPINS. A dragged tile the caller forgot to display still joins the pinned list rather than
	 * vanishing from it — a shape the strip does not show would otherwise be silently lost by a gesture. */
	if (fn_usable_identifier(dragged) && ![pinned containsObject:dragged]) {
		[pinned addObject:dragged];
	}
	fn_desktop_first(pinned);
	return pinned;
}

NSArray *DockOrderPinnedAdding(NSArray *pinnedIdentifiers, NSString *identifier)
{
	NSMutableArray *pinned = [NSMutableArray arrayWithArray:pinnedIdentifiers];

	if (!fn_usable_identifier(identifier) || [pinned containsObject:identifier]) {
		fn_desktop_first(pinned);
		return pinned;
	}
	[pinned addObject:identifier];
	fn_desktop_first(pinned);
	return pinned;
}

NSArray *DockOrderPinnedRemoving(NSArray *pinnedIdentifiers, NSString *identifier)
{
	NSMutableArray *pinned = [NSMutableArray arrayWithArray:pinnedIdentifiers];

	/* **THE DESKTOP CANNOT BE REMOVED, AND A DOOR THAT PRETENDED TO TRY WOULD BE THE ONE PATH THAT MADE A DOCK WITHOUT
	 * IT.** The menu does not offer the row for it and a drag cannot move it, so this is the third lock — the cheap
	 * one, and the one a future caller will still be held by. */
	if (fn_usable_identifier(identifier) && ![identifier isEqualToString:DockDesktopIdentifier]) {
		[pinned removeObject:identifier];
	}
	fn_desktop_first(pinned);
	return pinned;
}
