/*
 * DockLayout.m — the strip and the tiles, as arithmetic.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 */

#import "DockLayout.h"

const DockMetrics DockDefaultMetrics = {
	.width = 64.0,
	.tile = 48.0,
	.margin = 8.0,
	.spacing = 8.0,
	.separator = 12.0
};

NSRect DockStripRect(NSRect screenFrame, CGFloat menuBarHeight, DockOrientation orientation, DockMetrics metrics)
{
	CGFloat height = screenFrame.size.height - menuBarHeight;
	CGFloat x = (orientation == DockOrientationLeft) ? screenFrame.origin.x
							  : screenFrame.origin.x + screenFrame.size.width - metrics.width;

	if (height < 0.0) {
		height = 0.0;
	}
	/* THE STRIP ENDS WHERE THE BAR BEGINS: origin 0 and a height of `screen - menuBar`, which in Cocoa's bottom-up
	 * space is exactly "from the bottom of the screen up to the bottom of the bar". */
	return NSMakeRect(x, screenFrame.origin.y, metrics.width, height);
}

NSRect DockTileRect(NSRect strip, DockOrientation orientation, NSUInteger index, DockMetrics metrics)
{
	CGFloat top = strip.origin.y + strip.size.height;
	CGFloat y = top - metrics.margin - metrics.tile - ((CGFloat)index * (metrics.tile + metrics.spacing));
	CGFloat x = strip.origin.x + ((strip.size.width - metrics.tile) / 2.0);

	/* THE X WALK IS THE SAME FOR BOTH SIDES, because the strip is only as wide as the tile plus its margins: a
	 * left dock and a right dock differ in WHERE the strip is, not in how it is arranged. Centring rather than
	 * flushing is what keeps an icon off the screen's edge. */
	(void)orientation;
	return NSMakeRect(x, y, metrics.tile, metrics.tile);
}

NSRect DockTrashRect(NSRect strip, DockOrientation orientation, DockMetrics metrics)
{
	CGFloat x = strip.origin.x + ((strip.size.width - metrics.tile) / 2.0);
	CGFloat y = strip.origin.y + metrics.margin;

	(void)orientation;
	return NSMakeRect(x, y, metrics.tile, metrics.tile);
}

NSUInteger DockTilesThatFit(NSRect strip, DockMetrics metrics)
{
	CGFloat available = strip.size.height - (metrics.margin * 2.0) - metrics.tile - metrics.separator;

	if (available <= 0.0) {
		return 0;
	}
	/* THE FIRST TILE NEEDS ONLY ITS SIZE; every one after it needs a spacing too, which is what the `+ spacing`
	 * and the subtraction after the division say. */
	return (NSUInteger)((available + metrics.spacing) / (metrics.tile + metrics.spacing));
}
