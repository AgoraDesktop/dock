/*
 * dock_layout — the strip's geometry, with no window and no compositor.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * **WHAT IS ASSERTED IS WHERE THE DOCK IS AND WHERE THE TRASH IS.** The two things that were decided rather than
 * inherited are in this file: the strip is on a SIDE (right by default), and it ENDS AT THE MENU BAR rather than
 * sliding under it. The tiles then follow from the strip, and the one number that can go wrong silently is how many
 * fit before the trash — a Dock that draws a thirteenth icon through the bin is a Dock lying about where the bin is.
 *
 * 1280x720 with a 24-point bar is the screen every other geometry test in this tree uses, and 64/48/8/8/12 are
 * `DockDefaultMetrics`, so the expected numbers below are the defaults' arithmetic rather than a copy of it.
 */
#import <Foundation/NSGeometry.h>

#import "DockLayout.h"

#include <stdio.h>

static int s_failures;

static void check(int ok, const char *what)
{
	printf("  [%s] %s\n", ok ? "ok" : "FAIL", what);
	if (!ok) {
		s_failures++;
	}
}

static int rectsEqual(NSRect a, NSRect b)
{
	return a.origin.x == b.origin.x && a.origin.y == b.origin.y
	       && a.size.width == b.size.width && a.size.height == b.size.height;
}

int main(void)
{
	NSRect screen = NSMakeRect(0.0, 0.0, 1280.0, 720.0);
	NSRect right = DockStripRect(screen, 24.0, DockOrientationRight, DockDefaultMetrics);
	NSRect left = DockStripRect(screen, 24.0, DockOrientationLeft, DockDefaultMetrics);

	printf("dock_layout\n");

	/* ---- 1. the strip: a side, and never under the bar ---------------------------------- */
	check(rectsEqual(right, NSMakeRect(1216.0, 0.0, 64.0, 696.0)),
	      "the right strip is 64 wide, flush with the right edge, and 696 tall — the bar is not in it");
	check(rectsEqual(left, NSMakeRect(0.0, 0.0, 64.0, 696.0)),
	      "the left strip is the mirror, flush with the left edge");
	check(right.origin.y + right.size.height == screen.size.height - 24.0,
	      "its TOP is exactly where the menu bar begins, so it cannot overlap it");

	/* ---- 2. the tiles: from the top down, centred ---------------------------------------- */
	{
		NSRect first = DockTileRect(right, DockOrientationRight, 0, DockDefaultMetrics);
		NSRect second = DockTileRect(right, DockOrientationRight, 1, DockDefaultMetrics);

		check(first.size.width == 48.0 && first.size.height == 48.0, "a tile is 48 points square");
		check(first.origin.y == right.origin.y + right.size.height - 8.0 - 48.0,
		      "the first tile hangs 8 points below the strip's top");
		check(first.origin.y - second.origin.y == 48.0 + 8.0,
		      "and the next is one tile plus one spacing below it");
		check(first.origin.x == right.origin.x + 8.0,
		      "a tile is centred in the 64-point strip, which leaves 8 points on each side");
	}
	check(rectsEqual(DockTileRect(left, DockOrientationLeft, 0, DockDefaultMetrics),
			 NSMakeRect(8.0, 640.0, 48.0, 48.0)),
	      "the left Dock's tiles are the same rectangle, moved with the strip");

	/* ---- 3. the trash: pinned to the bottom ---------------------------------------------- */
	{
		NSRect trash = DockTrashRect(right, DockOrientationRight, DockDefaultMetrics);

		check(trash.origin.y == right.origin.y + 8.0, "the trash sits 8 points above the screen's bottom");
		check(trash.origin.x == 1224.0, "and is centred like every other tile");
	}

	/* ---- 4. how many fit, which is the number that can go wrong silently ----------------- */
	check(DockTilesThatFit(right, DockDefaultMetrics) == 11,
	      "eleven tiles fit above the trash on a 720-point screen");
	{
		/* A SHORT SCREEN: a 200-point screen minus the 24-point bar is a 176-point strip, so 176 - 16 - 48 - 12 =
		 * 100 points of tiles, and (100 + 8) / 56 = 1 — one tile above the trash, and no second one squeezed in. */
		NSRect shortStrip = DockStripRect(NSMakeRect(0.0, 0.0, 1280.0, 200.0), 24.0,
						  DockOrientationRight, DockDefaultMetrics);

		check(DockTilesThatFit(shortStrip, DockDefaultMetrics) == 1, "a short strip holds fewer");
		check(DockTilesThatFit(NSMakeRect(0.0, 0.0, 64.0, 40.0), DockDefaultMetrics) == 0,
		      "and a strip with no room for one says zero rather than a negative count");
	}

	/* ---- 5. and the strip that would be below zero is clamped --------------------------- */
	check(DockStripRect(screen, 800.0, DockOrientationRight, DockDefaultMetrics).size.height == 0.0,
	      "a menu bar taller than the screen gives a zero-height strip, not a negative one");

	printf("dock_layout: %d case(s) failed\n", s_failures);
	return s_failures == 0 ? 0 : 1;
}
