/*
 * dock_order — which tiles the strip shows and in what order, with no window and no compositor.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE FOUR RULES THIS FILE PINS ARE THE ONES A PERSON WOULD NOTICE.** A pinned application is on the strip whether
 * or not it is running; the running applications nobody pinned come after them; a drag PINS the tile it moves; and
 * the pin menu's two rows add and remove without duplicating. Each is arithmetic on bundle identifiers, so it is
 * asserted here rather than through a window — the same reason `dock_layout` exists: the part that can be wrong
 * without looking wrong is the part worth a test.
 *
 * THE TILES' OWN PERSISTENCE IS HERE TOO, because the pinned list is a FILE (a defaults plist that outlives the
 * build) and a round trip is the only thing that says so.
 *
 * AND THE DESKTOP'S THREE LOCKS: it appears once, it is FIRST, and no door in this file will remove it. Those are
 * asserted from the far side — a list that puts it last, a list that names it twice, and the "Remove from Dock" path
 * that the menu never offers for it.
 */
#import "DockOrder.h"
#import "DockTile.h"

#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>

#include <stdio.h>

static int s_failures;

static void check(int ok, const char *what)
{
	printf("  [%s] %s\n", ok ? "ok" : "FAIL", what);
	if (!ok) {
		s_failures++;
	}
}

/* TWO ARRAYS OF STRINGS, COMPARED BY WHAT THEY SAY rather than by identity: every door here answers a new array. */
static int sameStrings(NSArray *a, NSArray *b)
{
	NSUInteger i;

	if ([a count] != [b count]) {
		return 0;
	}
	for (i = 0; i < [a count]; i++) {
		if (![[a objectAtIndex:i] isEqual:[b objectAtIndex:i]]) {
			return 0;
		}
	}
	return 1;
}

/* A SMALL BUILDER, because a variadic list of C strings in a file that already has one is one too many. */
static NSArray *S(NSString *one, NSString *two, NSString *three, NSString *four, NSString *five)
{
	NSMutableArray *array = [NSMutableArray array];

	if (one != nil) [array addObject:one];
	if (two != nil) [array addObject:two];
	if (three != nil) [array addObject:three];
	if (four != nil) [array addObject:four];
	if (five != nil) [array addObject:five];
	return array;
}

int main(void)
{
	@autoreleasepool {
		/* THREE APPLICATIONS THAT ARE NOT THE DESKTOP: Workspace has a rule of its own (4b below), and a fixture
		 * that happened to BE Workspace would be testing that rule by accident in every case above it. */
		NSString *a = @"io.github.agoradesktop.forge";
		NSString *b = @"io.github.agoradesktop.notes";
		NSString *c = @"io.github.agoradesktop.terminal";
		NSArray *none = [NSArray array];

		printf("dock_order\n");

		/* ---- 1. the order: pins first, in their own order, then what is running ---- */
		check(sameStrings(DockOrderIdentifiers(none, S(c, a, nil, nil, nil)), S(c, a, nil, nil, nil)),
		      "with nothing pinned the strip is the running applications in the order they were named");
		check(sameStrings(DockOrderIdentifiers(S(b, nil, nil, nil, nil), S(c, a, nil, nil, nil)),
				  S(b, c, a, nil, nil)),
		      "a pinned application comes first, and the running ones follow it");
		check(sameStrings(DockOrderIdentifiers(S(b, c, nil, nil, nil), S(c, a, nil, nil, nil)),
				  S(b, c, a, nil, nil)),
		      "a pinned application that is ALSO running appears once, in its pinned place");
		check(sameStrings(DockOrderIdentifiers(S(b, b, nil, nil, nil), S(a, a, nil, nil, nil)),
				  S(b, a, nil, nil, nil)),
		      "and an identifier named twice appears once");
		check(sameStrings(DockOrderIdentifiers(none, none), none), "an empty Dock is empty");

		/* ---- 2. one drag step, which is a remove and an insert ---- */
		check(sameStrings(DockOrderMoving(S(a, b, c, nil, nil), 0, 2), S(b, c, a, nil, nil)),
		      "moving the first tile to the end keeps the others' order");
		check(sameStrings(DockOrderMoving(S(a, b, c, nil, nil), 2, 0), S(c, a, b, nil, nil)),
		      "and the last to the front does too");
		check(sameStrings(DockOrderMoving(S(a, b, c, nil, nil), 1, 1), S(a, b, c, nil, nil)),
		      "a move to where it already is changes nothing");
		check(sameStrings(DockOrderMoving(S(a, b, c, nil, nil), 1, 99), S(a, c, b, nil, nil)),
		      "a drop past the end is the end rather than a refusal");
		check(sameStrings(DockOrderMoving(S(a, nil, nil, nil, nil), 5, 0), S(a, nil, nil, nil, nil)),
		      "and a move from nowhere is a no-op");

		/* ---- 3. the release: the order becomes the pins, and the DRAGGED tile joins them ---- */
		check(sameStrings(DockOrderPinnedAfterMove(none, S(a, b, c, nil, nil), b), S(b, nil, nil, nil, nil)),
		      "dragging an unpinned tile PINS it — that is the rule, and it is why the order is written down");
		check(sameStrings(DockOrderPinnedAfterMove(S(a, c, nil, nil, nil), S(a, b, c, nil, nil), b),
				  S(a, b, c, nil, nil)),
		      "dropped between two pins, it lands between them");
		check(sameStrings(DockOrderPinnedAfterMove(S(c, nil, nil, nil, nil), S(a, c, b, nil, nil), b),
				  S(c, b, nil, nil, nil)),
		      "a running application that was merely DISPLAYED among the pins is not pinned by the drag");
		check(sameStrings(DockOrderPinnedAfterMove(S(a, nil, nil, nil, nil), S(a, b, nil, nil, nil), nil),
				  S(a, nil, nil, nil, nil)),
		      "and a drag with nothing being dragged leaves the pins alone");

		/* ---- 4. the menu's two rows ---- */
		check(sameStrings(DockOrderPinnedAdding(S(a, nil, nil, nil, nil), b), S(a, b, nil, nil, nil)),
		      "\"Keep in Dock\" appends");
		check(sameStrings(DockOrderPinnedAdding(S(a, b, nil, nil, nil), b), S(a, b, nil, nil, nil)),
		      "and does not pin the same application twice");
		check(sameStrings(DockOrderPinnedRemoving(S(a, b, c, nil, nil), b), S(a, c, nil, nil, nil)),
		      "\"Remove from Dock\" takes it out of the list and leaves the rest in order");
		check(sameStrings(DockOrderPinnedRemoving(S(a, nil, nil, nil, nil), c), S(a, nil, nil, nil, nil)),
		      "and removing something that is not there changes nothing");

		/* ---- 4b. the desktop: always there, always first, never removed ---- */
		{
			NSString *desktop = DockDesktopIdentifier;

			check(sameStrings(DockOrderIdentifiers(S(b, nil, nil, nil, nil), S(c, a, desktop, nil, nil)),
					  S(desktop, b, c, a, nil)),
			      "the desktop is first even when the running list names it last");
			check(sameStrings(DockOrderIdentifiers(S(b, desktop, c, nil, nil), S(a, nil, nil, nil, nil)),
					  S(desktop, b, c, a, nil)),
			      "and first even when the pinned list put it in the middle");
			check(sameStrings(DockOrderIdentifiers(S(desktop, desktop, nil, nil, nil), S(desktop, a, nil, nil, nil)),
					  S(desktop, a, nil, nil, nil)),
			      "a list that names it twice is one tile");
			check(sameStrings(DockOrderPinnedAfterMove(S(desktop, b, nil, nil, nil), S(b, desktop, nil, nil, nil),
								  b),
					  S(desktop, b, nil, nil, nil)),
			      "a drag cannot put anything above it");
			check(sameStrings(DockOrderPinnedRemoving(S(desktop, b, nil, nil, nil), desktop),
					  S(desktop, b, nil, nil, nil)),
			      "and \"Remove from Dock\" cannot take it away");
			check(sameStrings(DockOrderPinnedAdding(S(b, nil, nil, nil, nil), desktop),
					  S(desktop, b, nil, nil, nil)),
			      "while pinning ANYTHING, including the desktop itself, leaves it at the top");
		}

		/* ---- 5. a tile survives the process, which is what makes a pin a place ---- */
		{
			NSURL *url = [NSURL fileURLWithPath:@"/Applications/Agora Forge.app"];
			DockTile *pinned = [DockTile tileWithIdentifier:b
								 title:@"Forge"
							     bundleURL:url];
			NSDictionary *plist = [pinned propertyListRepresentation];
			DockTile *back = [DockTile tileWithPropertyListRepresentation:plist];

			check([pinned isPinned] && ![pinned isRunning],
			      "a tile made from the pinned list is PINNED and NOT RUNNING — the state a quit application leaves");
			check([[plist objectForKey:@"identifier"] isEqualToString:b] &&
			      [[plist objectForKey:@"title"] isEqualToString:@"Forge"] &&
			      [[plist objectForKey:@"path"] isEqualToString:@"/Applications/Agora Forge.app"],
			      "and it writes down the identifier, the name and the file");
			check(back != nil && [[back identifier] isEqualToString:b] &&
			      [[back title] isEqualToString:@"Forge"] &&
			      [[[back bundleURL] path] isEqualToString:@"/Applications/Agora Forge.app"],
			      "which come back as the same tile in the next process");
			check(back != nil && [back isPinned] && ![back isRunning],
			      "still pinned, and still not running until the snapshot says so");
		}
		/* A PIN A PREVIOUS RUN WROTE WITHOUT A FILE, which is what an identifier-only entry looks like. */
		{
			DockTile *named = [DockTile tileWithPropertyListRepresentation:
				[NSDictionary dictionaryWithObject:b forKey:@"identifier"]];

			check(named != nil && [[named identifier] isEqualToString:b] && [named bundleURL] == nil,
			      "an entry with no remembered file is a tile with no file, not a lost pin");
			check([DockTile tileWithPropertyListRepresentation:
				  [NSDictionary dictionaryWithObject:@"" forKey:@"identifier"]] == nil,
			      "and an entry with no identifier is refused rather than made into a nameless tile");
			check([DockTile tileWithIdentifier:@"" title:@"Nothing" bundleURL:nil] == nil,
			      "a tile cannot be made without an identifier at all");
		}

		/* **AND ONE PLACED AT A SLOT, WHICH IS WHAT A DROP FROM ANOTHER APPLICATION IS.** An application dropped between
		 * two pins belongs BETWEEN them — that is the whole of "pin it where I aimed" — and an application that is
		 * already a pin MOVES rather than appearing twice. The slot is a position in the array before the change, which is
		 * what a drop index is. */
		{
			NSArray *start = [NSArray arrayWithObjects:@"a.one", @"b.two", @"c.three", nil];
			NSArray *placed = DockOrderInsertingIdentifier(start, @"new.app", 1);

			check([placed count] == 4 && [[placed objectAtIndex:1] isEqualToString:@"new.app"],
			      "a dropped application is inserted at the slot it was aimed at");
			check([[placed objectAtIndex:0] isEqualToString:@"a.one"]
			      && [[placed objectAtIndex:2] isEqualToString:@"b.two"],
			      "with the pins either side of it unmoved");
			placed = DockOrderInsertingIdentifier(start, @"new.app", 0);
			check([[placed objectAtIndex:0] isEqualToString:@"new.app"], "slot 0 is the front of the list");
			placed = DockOrderInsertingIdentifier(start, @"new.app", 99);
			check([[placed lastObject] isEqualToString:@"new.app"], "and a slot past the end is the end");
			placed = DockOrderInsertingIdentifier(start, @"c.three", 0);
			check([placed count] == 3 && [[placed objectAtIndex:0] isEqualToString:@"c.three"],
			      "an application that is already a pin MOVES to the slot instead of appearing twice");
			{
				NSArray *same = DockOrderInsertingIdentifier(start, @"a.one", 0);

				check([same count] == 3 && [[same objectAtIndex:0] isEqualToString:@"a.one"],
				      "and one dropped on its own place is left where it is");
			}
			check([DockOrderInsertingIdentifier(start, @"", 1) count] == 3,
			      "an identifier nobody could write down changes nothing");
		}

		printf("dock_order: %d case(s) failed\n", s_failures);
	}
	return s_failures == 0 ? 0 : 1;
}
