/*
 * dock_badge — the two marks a tile draws, measured in pixels: its badge, and the dot that says it is running.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE VIEW IS DRAWN OFFSCREEN AND THE INK IS COUNTED**, which is the only way to test a drawing without a
 * compositor: a tile with a label must paint the badge's red in its top-right corner, the same tile with no label must
 * paint none, and a tile whose application is RUNNING must carry the white dot while a PINNED tile that is not running
 * must not. The applications are made here (`-cg_initWithBundleIdentifier:`), because the Dock's tiles come from the
 * workspace and a test that needed a real application's icon would need a real application.
 *
 * **AND THE DOT IS THE ONE CLAIM THAT CHANGED MEANING.** It used to mark the application with the keyboard, on the
 * argument that every tile was running by definition; a pinned tile is the counter-example that argument needed, so
 * the dot now marks the PROCESS and the case below draws three tiles at once — two running and one pinned-and-quit —
 * because a dot that marked "frontmost" would light one of them and this counts two.
 */
#import "DockView.h"
#import "DockLayout.h"
#import "DockTile.h"

#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSRunningApplication.h>

#include <stdio.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

#define W 72
#define H 240

/* THE CHIP'S COLOUR: `setBadgeLabels:`'s red, with a generous window either side of it. A pixel counts as badge ink when
 * it is decisively red and not the strip's grey-blue. */
static int is_badge_ink(unsigned char r, unsigned char g, unsigned char b)
{
	return r > 140 && g < 100 && b < 100;
}

/* **AND THE DOT'S: near-white, which nothing else on the strip is.** The band is 0.06/0.07/0.08 at 45% over nothing at
 * all, the placeholder icon is a muted grey-blue, and the badge is red, so a pixel above 200 in all three channels is
 * the indicator. */
static int is_indicator_ink(unsigned char r, unsigned char g, unsigned char b)
{
	return r > 200 && g > 200 && b > 200;
}

static int count_ink(NSBitmapImageRep *rep, NSRect area, int (*is_ink)(unsigned char, unsigned char, unsigned char))
{
	unsigned char *data = [rep bitmapData];
	NSInteger rowBytes = [rep bytesPerRow];
	int count = 0;
	int x, y;

	for (y = (int)NSMinY(area); y < (int)NSMaxY(area); y++) {
		for (x = (int)NSMinX(area); x < (int)NSMaxX(area); x++) {
			unsigned char *pixel = data + (H - 1 - y) * rowBytes + x * 4;

			if (is_ink(pixel[0], pixel[1], pixel[2])) {
				count++;
			}
		}
	}
	return count;
}

static NSBitmapImageRep *draw_view(DockView *view)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
		initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
			   bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
			   colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[view displayRectIgnoringOpacity:NSMakeRect(0, 0, W, H)
			      inContext:[NSGraphicsContext currentContext]];
	[NSGraphicsContext setCurrentContext:nil];
	return rep;
}

/* THE MARK'S BOX, taken from the layout rather than copied: the dot is 4 points wide, two points inside the tile's
 * inner edge, and the box counted is a little larger than the mark so a dot one point off is still measured as
 * present (or as absent, if it is absent). */
static NSRect indicator_box(DockView *view, NSUInteger index)
{
	NSRect bounds = [view bounds];
	NSRect tile = DockTileRect(bounds, DockOrientationRight, index, DockDefaultMetrics);

	return NSMakeRect(NSMinX(tile) - 8.0, NSMidY(tile) - 6.0, 8.0, 12.0);
}

int main(void)
{
	@autoreleasepool {
		/* TWO RUNNING APPLICATIONS, WITH THE IDENTIFIERS THE DOCK WOULD SEE. */
		NSRunningApplication *first =
			[[[NSRunningApplication alloc] cg_initWithBundleIdentifier:
				@"io.github.agoradesktop.probe"] autorelease];
		NSRunningApplication *second =
			[[[NSRunningApplication alloc] cg_initWithBundleIdentifier:
				@"io.github.agoradesktop.other"] autorelease];
		DockTile *firstTile = [DockTile tileWithApplication:first];
		DockTile *secondTile = [DockTile tileWithApplication:second];
		/* AND A PIN WITH NOTHING BEHIND IT: the state a quit application leaves on a Dock that keeps its place. */
		DockTile *pinnedTile = [DockTile tileWithIdentifier:@"io.github.agoradesktop.quit"
							      title:@"Quit"
							  bundleURL:nil];
		NSRect bounds = NSMakeRect(0, 0, W, H);
		NSRect tile = DockTileRect(bounds, DockOrientationRight, 0, DockDefaultMetrics);
		NSRect corner = NSMakeRect(NSMaxX(tile) - 20.0, NSMaxY(tile) - 20.0, 20.0, 20.0);
		DockView *view = [[DockView alloc] initWithFrame:bounds];
		NSBitmapImageRep *plain;
		NSBitmapImageRep *badged;
		NSBitmapImageRep *three;

		[view setOrientation:DockOrientationRight];
		[view setTiles:[NSArray arrayWithObject:firstTile]];

		plain = draw_view(view);
		check(count_ink(plain, corner, is_badge_ink) == 0,
		      "a tile with no label draws no badge");
		[plain release];

		[view setBadgeLabels:[NSDictionary dictionaryWithObject:@"7"
								forKey:@"io.github.agoradesktop.probe"]];
		badged = draw_view(view);
		check(count_ink(badged, corner, is_badge_ink) > 20,
		      "and a label paints a chip in the tile's top-right corner");
		[badged release];

		[view setBadgeLabels:[NSDictionary dictionary]];
		plain = draw_view(view);
		check(count_ink(plain, corner, is_badge_ink) == 0, "an empty dictionary is the same as no labels");
		[plain release];

		/* ---- 2. the dot marks the PROCESS ------------------------------------------------ */
		[view setTiles:[NSArray arrayWithObjects:firstTile, secondTile, pinnedTile, nil]];
		three = draw_view(view);
		check([firstTile isRunning] && [secondTile isRunning] && ![pinnedTile isRunning],
		      "the fixture is two running tiles and one pinned-and-quit one");
		check(count_ink(three, indicator_box(view, 0), is_indicator_ink) > 6,
		      "a running application's tile carries the dot");
		check(count_ink(three, indicator_box(view, 1), is_indicator_ink) > 6,
		      "AND SO DOES THE SECOND ONE: the dot is not a mark for the frontmost application, which only one of two"
		      " could wear");
		check(count_ink(three, indicator_box(view, 2), is_indicator_ink) == 0,
		      "and a pinned tile whose application has quit carries none — the place is dark until it comes back");
		[three release];

		printf("dock_badge: %d case(s) failed\n", s_failed);
		[view release];
	}
	return s_failed != 0;
}
