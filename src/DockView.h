/*
 * DockView.h — the strip's drawing, its hit test, and the drag that reorders a tile.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * The view owns NO model: it is handed the tiles to draw — `DockTile`, which is an application whether or not it is
 * running — and it reports a gesture as an INDEX, so the controller stays the only place that knows what a tile
 * means, which application is behind it and which order is written down. That split is what lets the layout and the
 * order be tested without a view and the view be tested without a compositor.
 *
 * **A PRESS IS NOT YET A CLICK.** The button going down starts a press, and what the gesture MEANS is decided by the
 * release: within a few points of where it started it is a click and the tile is invoked; past that it is a drag, the
 * tile is moved to wherever the pointer is over, and the release commits the order (the controller pins it). The view
 * does the arithmetic and tells the controller; the controller asks nobody.
 */
#ifndef DOCK_VIEW_H
#define DOCK_VIEW_H

#import <AppKit/NSView.h>

#import "DockLayout.h"

@class NSArray;
@class NSDictionary;
@class NSImage;

@interface DockView : NSView
{
@private
	NSArray *_tiles;			/* DockTile, in the order the Dock decided */
	NSDictionary *_badgeLabels;		/* bundle identifier -> the label its tile shows (NSDockTile) */
	DockOrientation _orientation;
	NSImage *_trashIcon;			/* resolved from the trash directory, and re-asked when it changes */
	long _trashStamp;			/* the directory's modification time the icon was resolved at */
	id _trashTimer;				/* RETAINED: the tick that notices the bin changed */
	BOOL _trashTarget;			/* a drag carrying files is over the trash tile */
	id _controller;				/* NOT retained: the controller owns this view */
	NSInteger _pressIndex;			/* the tile the button went down on, or DockHitNone */
	NSPoint _pressPoint;			/* where it went down: the drag's threshold is measured from here */
	BOOL _dragging;				/* the press became a drag, so the release moves rather than invokes */
	NSInteger _externalDropIndex;		/* the slot a drag from ANOTHER application would land in, or DockHitNone */
}

- (void)setTiles:(NSArray *)tiles;
/* **THE BADGES THE APPLICATIONS PUBLISHED**, keyed by bundle identifier; nil or empty clears them. */
- (void)setBadgeLabels:(NSDictionary *)labels;
- (void)setOrientation:(DockOrientation)orientation;
- (void)setController:(id)controller;

/* **WHETHER THE TRASH IS THE THING A DRAG IS OVER.** The tile a drop lands on is the strip's own hit test, and the
 * trash is the one slot that is not an application: a drop there is a file being thrown away. */
- (BOOL)cg_trashIsDropTarget;

/* WHICH TILE A POINT IS OVER: an application index, the trash, or nothing. The view's own hit test, which is why
 * the click does not have to recompute the layout in the controller. */
typedef enum {
	DockHitNone = -1,
	DockHitTrash = -2
} DockHit;

- (NSInteger)hitTestTileAtPoint:(NSPoint)point;

/* **WHERE A DROPPED TILE WOULD GO**, which is a different question from what is under the pointer: a drag aims at a
 * SLOT. A point above the first tile is slot 0, a point below the last shown one is the last slot, and a point in the
 * trash or past it is the last slot too — the trash is not a drop target yet, and a drag that ends on it must not
 * leave the tile nowhere. Answers DockHitNone only when there is no tile to move. */
- (NSInteger)tileIndexForDropAtPoint:(NSPoint)point;

/* **AND THE SLOT AN EXTERNAL DRAG IS AIMING AT, WHICH THE STRIP DRAWS AS AN INSERTION MARK.** A drag from another
 * application carries file names; the strip reports where a drop would put them and answers the drag-operation mask, so
 * a person sees the slot before letting go. DockHitNone means no drag is over the strip. */
- (NSInteger)externalDropIndex;

@end

#endif /* DOCK_VIEW_H */
