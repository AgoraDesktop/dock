/*
 * DockView.m — the flat semitransparent band, the icons, and the dot that means "this one is running".
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * **THE BACKGROUND IS DRAWN BY THE VIEW AND NOT BY THE WINDOW**, because the window is transparent: the compositor
 * blends the strip over the wallpaper, and everything the view does not paint stays transparent. The strip is FLAT
 * — square corners, no inset, no border — because it belongs to the screen's edge rather than floating over the
 * desktop: the mockup shows one dark semitransparent band from the menu bar down, and a shape is what tells a
 * person which of the two Docks they are looking at.
 *
 * **THE DOTTED INDICATOR IS "RUNNING", AND IT IS NOW THE MAC'S MEANING RATHER THAN THE OPPOSITE ONE.** It used to mark
 * the application with the keyboard, on the argument that every tile was running by definition — which was true while
 * the strip was a list of RUNNING APPLICATIONS and stopped being true when a tile could be pinned. A pinned
 * application keeps its place while it is quit, so the strip now shows both kinds, and the dot is what tells them
 * apart: lit for the ones with a process, dark for the place a quit application will come back to.
 */
#import "DockView.h"
#import "DockController.h"
#import "DockTile.h"

#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSWorkspace.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSString.h>

#include <math.h>

/* **WHAT THE VIEW ASKS ITS CONTROLLER FOR, DECLARED WHERE IT IS CALLED.** The view reports tile POSITIONS and the
 * controller decides what they mean; declaring the messages here keeps the view free of the controller's header and
 * the controller free of the view's — the same informal-protocol shape `NSStatusItem.m` uses for the window door it
 * calls. */
@interface NSObject (DockViewActions)
- (void)activateTileAtIndex:(NSNumber *)index;
- (void)showMenuForTileAtIndex:(NSNumber *)index withEvent:(id)event;
- (void)moveTileFromIndex:(NSNumber *)from toIndex:(NSNumber *)to;
- (void)commitTileOrder;
- (void)cancelTileOrder;
@end

/* **THE DOT LIVES IN THE EIGHT-POINT MARGIN, WHICH IS THE ONLY PLACE IT CAN BE SEEN.** With a 48-point tile in a
 * 64-point band the inner margin is 8 points; a 4-point dot two points into it is the widest mark that still fits. At
 * the old 5-point dot and 6-point gap the mark was placed at x = -3 — off the view — so the indicator was drawn
 * nowhere at all. */
#define DOCK_INDICATOR_SIZE	4.0
#define DOCK_INDICATOR_GAP	2.0

/* **HOW FAR A HAND MAY SHAKE AND STILL BE CLICKING.** A press that moves less than this in both axes is a click — a
 * person pressing a tile is not a person dragging one, and a two-point drift must not reorder the strip. Four points
 * is about the width of the pointer's own arrow, which is the same threshold a Mac Dock uses in spirit. */
#define DOCK_DRAG_SLOP	4.0

@implementation DockView

- (id)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame]) != nil) {
		_tiles = [[NSArray alloc] init];
		_pressIndex = (NSInteger)DockHitNone;
		_externalDropIndex = (NSInteger)DockHitNone;
		/* **THE STRIP IS A DROP TARGET FOR APPLICATIONS THE DOCK DOES NOT HAVE YET.** A file-name list is what every
		 * application's drag supplies — Workspace's icon view puts exactly that on the pasteboard — and it is the only
		 * type this view asks for: a drag of text or of an image has nothing to pin. */
		[self registerForDraggedTypes:[NSArray arrayWithObject:NSFilenamesPboardType]];
	}
	return self;
}

- (void)dealloc
{
	[_tiles release];
	[_badgeLabels release];
	[_trashIcon release];
	[super dealloc];
}

- (void)setTiles:(NSArray *)tiles
{
	NSArray *copy = [tiles copy];

	[_tiles release];
	_tiles = copy;
	[self setNeedsDisplay:YES];
}

/* **A BADGE IS A CHIP ON THE ICON'S OUTER CORNER**, which is the Mac's own answer and the only place a label fits on a
 * 48-point tile: counted from the icon's top-right, right-aligned on a right-hand Dock so it grows inward. An
 * application with no label in the dictionary draws nothing, which is the ordinary case.
 */
- (void)setBadgeLabels:(NSDictionary *)labels
{
	NSDictionary *copy = [labels copy];

	[_badgeLabels release];
	_badgeLabels = copy;
}

- (void)drawBadgeForIdentifier:(NSString *)identifier inTile:(NSRect)tile
{
	NSString *label;
	NSDictionary *attributes;
	NSSize size;
	CGFloat padding = 4.0;
	NSRect chip;

	if (_badgeLabels == nil || identifier == nil) {
		return;
	}
	label = [_badgeLabels objectForKey:identifier];
	if (label == nil || [label length] == 0) {
		return;
	}
	attributes = [NSDictionary dictionaryWithObjectsAndKeys:
		[NSFont boldSystemFontOfSize:10.0], NSFontAttributeName,
		[NSColor whiteColor], NSForegroundColorAttributeName, nil];
	size = [label sizeWithAttributes:attributes];
	chip = NSMakeRect(NSMaxX(tile) - (size.width + 2.0 * padding),
			  NSMaxY(tile) - (size.height + 2.0 * padding),
			  size.width + 2.0 * padding, size.height + 2.0 * padding);
	/* A CHIP THAT WOULD RUN OFF A NARROW TILE IS CLAMPED TO IT rather than drawn outside the strip. */
	if (NSMinX(chip) < NSMinX(tile)) {
		chip.origin.x = NSMinX(tile);
		chip.size.width = NSWidth(tile);
	}
	[[NSColor colorWithCalibratedRed:0.85 green:0.18 blue:0.16 alpha:0.95] setFill];
	[[NSBezierPath bezierPathWithRoundedRect:chip xRadius:(NSHeight(chip) / 2.0) yRadius:(NSHeight(chip) / 2.0)] fill];
	[label drawAtPoint:NSMakePoint(NSMinX(chip) + padding, NSMinY(chip) + padding) withAttributes:attributes];
}

- (void)setOrientation:(DockOrientation)orientation
{
	_orientation = orientation;
	[self setNeedsDisplay:YES];
}

- (void)setController:(id)controller
{
	_controller = controller;	/* NOT retained: the controller owns this view */
}

/* THE TRASH'S ICON IS THE ICON OF THE TRASH DIRECTORY — that is the Mac's own answer: `NSWorkspace -iconForFile:`
 * on `~/.Trash` returns the can, and Icon Services already maps that exact path to the theme's `user-trash` place icon
 * (`AGIconLoader.c`, `placeNameForPath`).
 *
 * **SO THE DIRECTORY HAS TO EXIST, AND ON A FRESH INSTALL IT DOES NOT.** Nothing has been thrown away yet, so there is
 * no `~/.Trash` to look up: `stat` fails, the path is not a directory, and the icon that comes back is a GENERIC FILE —
 * a piece of paper in the Dock's trash slot. MEASURED, in the session, which is why this creates it. The session does
 * the same at login (`demo/agora-session.sh`), because that is the Mac's arrangement: the directory is the user's, not
 * a window's. The Dock creates it here only so that a Dock started on its own is not wrong; `WSTrash` will be the one
 * that owns recycling, Put Back and per-volume semantics (WORKSPACE-PLAN.md §5.3). */
- (NSImage *)trashIcon
{
	if (_trashIcon == nil) {
		NSString *home = NSHomeDirectory();

		if (home != nil) {
			NSString *trash = [home stringByAppendingPathComponent:@".Trash"];
			NSFileManager *files = [NSFileManager defaultManager];

			if (![files fileExistsAtPath:trash]) {
				[files createDirectoryAtPath:trash withIntermediateDirectories:NO attributes:nil error:NULL];
			}
			_trashIcon = [[[NSWorkspace sharedWorkspace] iconForFile:trash] retain];
		}
	}
	return _trashIcon;
}

/* ---------------------------------------------------------------------------------------------------
 * the hit test
 * --------------------------------------------------------------------------------------------------- */

/* HOW MANY TILES THE STRIP SHOWS: the ones it has, or as many as fit above the trash, whichever is fewer. */
- (NSUInteger)shownTileCount
{
	NSUInteger count = [_tiles count];
	NSUInteger fits = DockTilesThatFit([self bounds], DockDefaultMetrics);

	return (count < fits) ? count : fits;
}

- (NSInteger)hitTestTileAtPoint:(NSPoint)point
{
	NSUInteger shown = [self shownTileCount];
	NSUInteger i;

	for (i = 0; i < shown; i++) {
		if (NSPointInRect(point, DockTileRect([self bounds], _orientation, i, DockDefaultMetrics))) {
			return (NSInteger)i;
		}
	}
	if (NSPointInRect(point, DockTrashRect([self bounds], _orientation, DockDefaultMetrics))) {
		return DockHitTrash;
	}
	return DockHitNone;
}

- (NSInteger)tileIndexForDropAtPoint:(NSPoint)point
{
	NSUInteger shown = [self shownTileCount];
	NSRect first;
	CGFloat pitch;
	NSInteger index;

	if (shown == 0) {
		return DockHitNone;
	}
	/* **THE SLOTS ARE THE TILE RECTS AND THE AIR BETWEEN THEM**, so the answer is the layout's own arithmetic rather
	 * than a second copy of it: the first tile's top edge is the top of slot 0, and every pitch below it is one more.
	 * A point above the first tile is slot 0 and one below the last is the last slot, because a drag aims at a slot
	 * and the strip has no place outside itself to aim at. */
	first = DockTileRect([self bounds], _orientation, 0, DockDefaultMetrics);
	pitch = DockDefaultMetrics.tile + DockDefaultMetrics.spacing;
	index = (NSInteger)floor((NSMaxY(first) - point.y) / pitch);
	if (index < 0) {
		index = 0;
	}
	if (index > (NSInteger)shown - 1) {
		index = (NSInteger)shown - 1;
	}
	return index;
}

/* ---------------------------------------------------------------------------------------------------
 * the gesture: a press, then either a click or a drag
 * --------------------------------------------------------------------------------------------------- */

- (void)mouseDown:(id)event
{
	NSPoint where = [self convertPoint:[event locationInWindow] fromView:nil];
	NSInteger hit = [self hitTestTileAtPoint:where];

	/* **A NEW PRESS FORGETS THE LAST ONE, AND THAT IS THE RECOVERY PATH.** A release that never arrived — the hand
	 * left the strip and came up over somebody else's window — would otherwise leave this view dragging a tile for
	 * good, with the strip showing an order nobody committed. The next press on the Dock restores the order that is
	 * written down, and starts its own gesture. */
	if (_dragging && _controller != nil) {
		[_controller cancelTileOrder];
	}
	_pressIndex = (hit >= 0) ? hit : (NSInteger)DockHitNone;
	_pressPoint = where;
	_dragging = NO;
	/* THE TRASH DOES NOTHING YET, AND THAT IS THE W3/W7 BOUNDARY: its icon is the Dock's, but what a click MEANS
	 * — a file window on `~/.Trash` — is Workspace's, and the contract between the two is §5.3 of the plan and is
	 * still undecided. A drop on it is the same contract from the other side, which is why a drop there lands on the
	 * last tile instead. */
}

- (void)mouseDragged:(id)event
{
	NSPoint where = [self convertPoint:[event locationInWindow] fromView:nil];
	NSInteger target;

	if (_pressIndex < 0 || _controller == nil) {
		return;
	}
	if (!_dragging) {
		if (fabs((double)(where.y - _pressPoint.y)) < DOCK_DRAG_SLOP &&
		    fabs((double)(where.x - _pressPoint.x)) < DOCK_DRAG_SLOP) {
			return;	/* still a click's worth of shake */
		}
		_dragging = YES;
	}
	target = [self tileIndexForDropAtPoint:where];
	if (target < 0 || target == _pressIndex) {
		return;
	}
	/* THE MOVE IS LIVE: the tile follows the pointer, and the release is what PINS and WRITES the order down. */
	[_controller moveTileFromIndex:[NSNumber numberWithInteger:_pressIndex]
			       toIndex:[NSNumber numberWithInteger:target]];
	_pressIndex = target;
}

- (void)mouseUp:(id)event
{
	NSInteger index = _pressIndex;
	BOOL dragged = _dragging;

	(void)event;
	_pressIndex = (NSInteger)DockHitNone;
	_dragging = NO;
	if (index < 0 || _controller == nil) {
		return;
	}
	if (dragged) {
		[_controller commitTileOrder];
	} else {
		[_controller activateTileAtIndex:[NSNumber numberWithInteger:index]];
	}
}

- (void)rightMouseDown:(id)event
{
	NSPoint where = [self convertPoint:[event locationInWindow] fromView:nil];
	NSInteger hit = [self hitTestTileAtPoint:where];

	if (hit >= 0 && _controller != nil) {
		[_controller showMenuForTileAtIndex:[NSNumber numberWithInteger:hit] withEvent:event];
	}
}

/* ---------------------------------------------------------------------------------------------------
 * a drag from ANOTHER application: the slot, and the pin
 * --------------------------------------------------------------------------------------------------- */

/* **ONLY AN APPLICATION BUNDLE IS SOMETHING TO PIN, AND THIS IS THE ONE PLACE THAT IS DECIDED FOR A DRAG.** The name list
 * is filtered through `DockTile`'s own constructor rather than by extension here, so "what the Dock will pin" has one
 * answer shared by the drop, the menu and the defaults. */
static NSArray *fn_application_paths(id <NSDraggingInfo> info)
{
	NSArray *names = [[info draggingPasteboard] propertyListForType:NSFilenamesPboardType];
	NSMutableArray *paths = [NSMutableArray array];
	NSUInteger i;

	if (![names isKindOfClass:[NSArray class]]) {
		return paths;
	}
	for (i = 0; i < [names count]; i++) {
		id path = [names objectAtIndex:i];

		if ([path isKindOfClass:[NSString class]] && [DockTile tileWithApplicationBundleAtPath:path] != nil) {
			[paths addObject:path];
		}
	}
	return paths;
}

- (NSInteger)externalDropIndex
{
	return _externalDropIndex;
}

- (void)fn_setExternalDropIndex:(NSInteger)index
{
	if (_externalDropIndex == index) {
		return;
	}
	_externalDropIndex = index;
	[self setNeedsDisplay:YES];
}

/* **THE SLOT IS WHERE THE POINTER IS, WHICH IS THE SAME ARITHMETIC A TILE'S OWN DRAG USES.** The strip answers the drag
 * mask for an application and nothing for anything else, so a document dragged over the Dock is a drag the Dock does not
 * want rather than one it takes and then ignores. */
- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)info
{
	NSPoint where = [self convertPoint:[info draggingLocation] fromView:nil];

	if ([fn_application_paths(info) count] == 0) {
		[self fn_setExternalDropIndex:(NSInteger)DockHitNone];
		return NSDragOperationNone;
	}
	[self fn_setExternalDropIndex:[self tileIndexForDropAtPoint:where]];
	return NSDragOperationCopy;
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)info
{
	return [self draggingEntered:info];
}

- (void)draggingExited:(id <NSDraggingInfo>)info
{
	(void)info;
	[self fn_setExternalDropIndex:(NSInteger)DockHitNone];
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)info
{
	return [fn_application_paths(info) count] > 0;
}

/* **THE DROP PINS WHERE IT WAS AIMED, AND THE SLOT IS THE WHOLE OF "WHERE".** A slot past the last tile (the pointer was
 * over the trash, or below the strip) is the end of the pinned list, which is where a Dock puts a new tile, and the
 * controller owns that arithmetic — the view only says which slot and which applications. */
- (BOOL)performDragOperation:(id <NSDraggingInfo>)info
{
	NSArray *paths = fn_application_paths(info);
	NSInteger index = _externalDropIndex;
	BOOL pinned = NO;

	if (getenv("AGORA_DRAG_DIAG") != NULL) {
		fprintf(stderr, "  DIAG dock: perform with %lu path(s), slot %ld, controller %p\n",
			(unsigned long)[paths count], (long)index, (void *)_controller);
	}
	if ([paths count] > 0 && _controller != nil) {
		pinned = [(DockController *)_controller pinApplicationPaths:paths atIndex:index];
	}
	if (getenv("AGORA_DRAG_DIAG") != NULL) {
		fprintf(stderr, "  DIAG dock: pinned %d\n", (int)pinned);
	}
	[self fn_setExternalDropIndex:(NSInteger)DockHitNone];
	return pinned;
}

/* ---------------------------------------------------------------------------------------------------
 * drawing
 * --------------------------------------------------------------------------------------------------- */

- (void)drawRect:(NSRect)dirtyRect
{
	NSUInteger shown = [self shownTileCount];
	NSUInteger i;

	(void)dirtyRect;
	/* **FLAT, SEMITRANSPARENT, AND DARKER THAN WHAT IS BEHIND IT — the mockup's band, not a shelf.** No rounded
	 * corners, no inset, no border: the strip is a SHADE over the wallpaper, edge to edge, so a person sees the
	 * desktop underneath with the Dock's tiles on it. The Mac's Dock floats; Agora's belongs to the screen's edge, and
	 * that is a difference of shape, not of colour. */
	[[NSColor colorWithCalibratedRed:0.06 green:0.07 blue:0.08 alpha:0.45] setFill];
	[NSBezierPath fillRect:[self bounds]];

	for (i = 0; i < shown; i++) {
		DockTile *tile = [_tiles objectAtIndex:i];
		NSRect rect = DockTileRect([self bounds], _orientation, i, DockDefaultMetrics);
		NSImage *icon = [tile icon];

		if (icon != nil) {
			[icon drawInRect:rect];
		} else {
			/* NO BUNDLE, NO ICON: a muted rounded square rather than nothing, so the tile is still a target a
			 * person can see and click. */
			NSBezierPath *placeholder = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:9.0 yRadius:9.0];

			[[NSColor colorWithCalibratedRed:0.35 green:0.38 blue:0.42 alpha:1.0] setFill];
			[placeholder fill];
		}
		[self drawBadgeForIdentifier:[tile identifier] inTile:rect];
		if ([tile isRunning]) {
			/* THE DOT ON THE INNER SIDE: right of the icon on a left dock, left of it on a right dock. */
			CGFloat x = (_orientation == DockOrientationRight)
					    ? rect.origin.x - DOCK_INDICATOR_GAP - DOCK_INDICATOR_SIZE
					    : rect.origin.x + rect.size.width + DOCK_INDICATOR_GAP;
			NSRect dot = NSMakeRect(x, NSMidY(rect) - (DOCK_INDICATOR_SIZE / 2.0),
						DOCK_INDICATOR_SIZE, DOCK_INDICATOR_SIZE);
			NSBezierPath *indicator = [NSBezierPath bezierPathWithOvalInRect:dot];

			[[NSColor colorWithCalibratedRed:0.98 green:0.98 blue:0.98 alpha:0.95] setFill];
			[indicator fill];
		}
	}

	/* **AND THE SLOT A DRAG FROM OUTSIDE WOULD LAND IN, DRAWN AS AN INSERTION MARK.** The tiles do not make room for it —
	 * the drop happens on the release — so the mark says where the tile WILL be: a bar in the gap above the tile that is
	 * there now, in the accent colour every other mark on this desktop uses. A slot below the last tile has no tile to
	 * sit above, so the mark goes under the last one, which is the same place the drop will put it. */
	if (_externalDropIndex != (NSInteger)DockHitNone && shown > 0) {
		NSUInteger slot = (NSUInteger)_externalDropIndex;
		NSRect tile = DockTileRect([self bounds], _orientation, (slot < shown) ? slot : shown - 1,
					   DockDefaultMetrics);
		CGFloat thickness = 3.0;
		NSRect mark = NSMakeRect(tile.origin.x - 2.0,
					 (slot < shown) ? NSMaxY(tile) + (DockDefaultMetrics.spacing / 2.0) - (thickness / 2.0)
							: NSMinY(tile) - (DockDefaultMetrics.spacing / 2.0) - (thickness / 2.0),
					 tile.size.width + 4.0, thickness);
		NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:mark xRadius:thickness / 2.0
								      yRadius:thickness / 2.0];

		[[NSColor cg_accentColor] setFill];
		[path fill];
	}

	/* AND THE TRASH, LAST AND AT THE BOTTOM. */
	{
		NSRect trash = DockTrashRect([self bounds], _orientation, DockDefaultMetrics);
		NSImage *icon = [self trashIcon];

		if (icon != nil) {
			[icon drawInRect:trash];
		} else {
			NSBezierPath *placeholder = [NSBezierPath bezierPathWithRoundedRect:trash xRadius:9.0 yRadius:9.0];

			[[NSColor colorWithCalibratedRed:0.45 green:0.45 blue:0.48 alpha:1.0] setFill];
			[placeholder fill];
		}
	}
}

@end
