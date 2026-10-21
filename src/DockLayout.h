/*
 * DockLayout.h — where the strip is and where each tile goes. Geometry only: no window, no drawing, no server.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * **THE DOCK IS VERTICAL, AND IT IS ON A SIDE RATHER THAN THE BOTTOM.** It runs from the menu bar down to the
 * bottom of the screen, flush with the right edge (or the left, when the user says so), and it NEVER goes under the
 * bar: the bar is the server's strip at level 24 and the Dock sits at level 20, so a Dock drawn into those rows
 * would be covered by the bar and look cut off. The strip therefore starts at `menuBarHeight` in Cocoa's
 * bottom-up coordinates — that is, it ends where the bar ends.
 *
 * **COCOA'S ORIGIN IS THE BOTTOM-LEFT, AND THAT DECIDES THE WALK.** A vertical Dock stacks from the TOP downwards,
 * which in this coordinate space is a walk from the strip's `origin.y + size.height` towards `origin.y`. The trash
 * is pinned at the BOTTOM, so it stays put while applications come and go — the same place it has on the Mac.
 *
 * Everything here is a pure function of rectangles, which is what makes the layout testable with no compositor and
 * no pixels (`tests/dock_layout.m`).
 */
#ifndef DOCK_LAYOUT_H
#define DOCK_LAYOUT_H

#import <Foundation/NSGeometry.h>

/** Which side of the screen the strip is on. Right is the default; left is the alternative. */
typedef enum {
	DockOrientationRight = 0,
	DockOrientationLeft = 1
} DockOrientation;

/* THE FIVE NUMBERS THE STRIP IS MADE OF, in points. A tile is 44 and the strip 64, which leaves ten points of air
 * on each side of an icon; the margin is the strip's own inset, the spacing is between two tiles, and the separator
 * is the gap the trash sits below. */
typedef struct {
	CGFloat width;
	CGFloat tile;
	CGFloat margin;
	CGFloat spacing;
	CGFloat separator;
} DockMetrics;

extern const DockMetrics DockDefaultMetrics;

/* **THE STRIP, IN COCOA'S SCREEN FRAME.** `screenFrame` is `[NSScreen frame]` — the whole screen, not
 * `visibleFrame`, because the Dock is furniture and not a window being placed in what is left. */
NSRect DockStripRect(NSRect screenFrame, CGFloat menuBarHeight, DockOrientation orientation, DockMetrics metrics);

/* Where tile `index` goes — the walk from the top. Index 0 is the highest. */
NSRect DockTileRect(NSRect strip, DockOrientation orientation, NSUInteger index, DockMetrics metrics);

/* The trash's tile, pinned to the strip's bottom. */
NSRect DockTrashRect(NSRect strip, DockOrientation orientation, DockMetrics metrics);

/* **HOW MANY APPLICATION TILES FIT ABOVE THE TRASH.** A vertical strip has a finite height, and a Dock that drew
 * its thirteenth icon through the trash would be lying about where the trash is. The caller draws this many and no
 * more; the rest are simply not shown, which is the honest degradation of a strip with no overflow affordance yet. */
NSUInteger DockTilesThatFit(NSRect strip, DockMetrics metrics);

#endif /* DOCK_LAYOUT_H */
