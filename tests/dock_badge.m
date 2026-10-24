/*
 * dock_badge — the badge a tile draws, measured in pixels.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE VIEW IS DRAWN OFFSCREEN AND THE CHIP IS COUNTED**, which is the only way to test a drawing without a compositor:
 * a tile with a label must paint the badge's red in its top-right corner, and the same tile with no label must paint
 * none. The application is made here (`-cg_initWithBundleIdentifier:`), because the Dock's tiles come from the
 * workspace and a test that needed a real application's icon would need a real application.
 */
#import "DockView.h"
#import "DockLayout.h"

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
#define H 160

/* THE CHIP'S COLOUR: `setBadgeLabels:`'s red, with a generous window either side of it. A pixel counts as badge ink when
 * it is decisively red and not the strip's grey-blue. */
static int is_badge_ink(unsigned char r, unsigned char g, unsigned char b)
{
	return r > 140 && g < 100 && b < 100;
}

static int count_badge_ink(NSBitmapImageRep *rep, NSRect area)
{
	unsigned char *data = [rep bitmapData];
	NSInteger rowBytes = [rep bytesPerRow];
	int count = 0;
	int x, y;

	for (y = (int)NSMinY(area); y < (int)NSMaxY(area); y++) {
		for (x = (int)NSMinX(area); x < (int)NSMaxX(area); x++) {
			unsigned char *pixel = data + (H - 1 - y) * rowBytes + x * 4;

			if (is_badge_ink(pixel[0], pixel[1], pixel[2])) {
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

int main(void)
{
	@autoreleasepool {
		NSRunningApplication *application =
			[[[NSRunningApplication alloc] cg_initWithBundleIdentifier:
				@"io.github.agoradesktop.probe"] autorelease];
		NSRect bounds = NSMakeRect(0, 0, W, H);
		NSRect tile = DockTileRect(bounds, DockOrientationRight, 0, DockDefaultMetrics);
		NSRect corner = NSMakeRect(NSMaxX(tile) - 20.0, NSMaxY(tile) - 20.0, 20.0, 20.0);
		DockView *view = [[DockView alloc] initWithFrame:bounds];
		NSBitmapImageRep *plain;
		NSBitmapImageRep *badged;

		[view setOrientation:DockOrientationRight];
		[view setApplications:[NSArray arrayWithObject:application]];

		plain = draw_view(view);
		check(count_badge_ink(plain, corner) == 0,
		      "a tile with no label draws no badge");
		[plain release];

		[view setBadgeLabels:[NSDictionary dictionaryWithObject:@"7"
								forKey:@"io.github.agoradesktop.probe"]];
		badged = draw_view(view);
		check(count_badge_ink(badged, corner) > 20,
		      "and a label paints a chip in the tile's top-right corner");
		[badged release];

		[view setBadgeLabels:[NSDictionary dictionary]];
		plain = draw_view(view);
		check(count_badge_ink(plain, corner) == 0, "an empty dictionary is the same as no labels");
		[plain release];

		printf("dock_badge: %d case(s) failed\n", s_failed);
		[view release];
	}
	return s_failed != 0;
}
