/*
 * DockView.m — the flat semitransparent band, the icons, and the one dot that means "this one has the keyboard".
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
 * **THE DOTTED INDICATOR IS THE ACTIVE APPLICATION, NOT "RUNNING".** Every tile in this Dock is a running
 * application (the list it draws comes from `NSWorkspace -runningApplications`), so a Mac-style running dot on all
 * of them would carry no information. The one thing that changes is which of them has the keyboard, and that is
 * what the dot marks.
 */
#import "DockView.h"

#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSRunningApplication.h>
#import <AppKit/NSWorkspace.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSString.h>

/* **WHAT THE VIEW ASKS ITS CONTROLLER FOR, DECLARED WHERE IT IS CALLED.** The view reports a tile INDEX and the
 * controller decides what that means; declaring the two messages here keeps the view free of the controller's
 * header and the controller free of the view's — the same informal-protocol shape `NSStatusItem.m` uses for the
 * window door it calls. */
@interface NSObject (DockViewActions)
- (void)activateTileAtIndex:(NSNumber *)index;
- (void)showMenuForTileAtIndex:(NSNumber *)index withEvent:(id)event;
@end

/* **THE DOT LIVES IN THE EIGHT-POINT MARGIN, WHICH IS THE ONLY PLACE IT CAN BE SEEN.** With a 48-point tile in a
 * 64-point band the inner margin is 8 points; a 4-point dot two points into it is the widest mark that still fits. At
 * the old 5-point dot and 6-point gap the mark was placed at x = -3 — off the view — so the indicator was drawn
 * nowhere at all. */
#define DOCK_INDICATOR_SIZE	4.0
#define DOCK_INDICATOR_GAP	2.0

@implementation DockView

- (id)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame]) != nil) {
		_applications = [[NSArray alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[_applications release];
	[_badgeLabels release];
	[_trashIcon release];
	[super dealloc];
}

- (void)setApplications:(NSArray *)applications
{
	NSArray *copy = [applications copy];

	[_applications release];
	_applications = copy;
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

- (void)drawBadgeForApplication:(NSRunningApplication *)application inTile:(NSRect)tile
{
	NSString *label;
	NSDictionary *attributes;
	NSSize size;
	CGFloat padding = 4.0;
	NSRect chip;

	if (_badgeLabels == nil || [application bundleIdentifier] == nil) {
		return;
	}
	label = [_badgeLabels objectForKey:[application bundleIdentifier]];
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

- (void)setActiveApplication:(NSRunningApplication *)application
{
	if (_active == application) {
		return;
	}
	[application retain];
	[_active release];
	_active = application;
	[self setNeedsDisplay:YES];
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

- (NSInteger)hitTestTileAtPoint:(NSPoint)point
{
	NSUInteger count = [_applications count];
	NSUInteger fits = DockTilesThatFit([self bounds], DockDefaultMetrics);
	NSUInteger shown = (count < fits) ? count : fits;
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

- (void)mouseDown:(id)event
{
	NSPoint where = [self convertPoint:[event locationInWindow] fromView:nil];
	NSInteger hit = [self hitTestTileAtPoint:where];

	if (hit >= 0 && _controller != nil) {
		[_controller activateTileAtIndex:[NSNumber numberWithInteger:hit]];
	}
	/* THE TRASH DOES NOTHING YET, AND THAT IS THE W3/W7 BOUNDARY: its icon is the Dock's, but what a click MEANS
	 * — a file window on `~/.Trash` — is Workspace's, and the contract between the two is §5.3 of the plan and is
	 * still undecided. A drop on it is the same contract from the other side. */
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
 * drawing
 * --------------------------------------------------------------------------------------------------- */

- (void)drawRect:(NSRect)dirtyRect
{
	NSUInteger count = [_applications count];
	NSUInteger fits = DockTilesThatFit([self bounds], DockDefaultMetrics);
	NSUInteger shown = (count < fits) ? count : fits;
	NSUInteger i;

	(void)dirtyRect;
	/* **FLAT, SEMITRANSPARENT, AND DARKER THAN WHAT IS BEHIND IT — the mockup's band, not a shelf.** No rounded
	 * corners, no inset, no border: the strip is a SHADE over the wallpaper, edge to edge, so a person sees the
	 * desktop underneath with the Dock's tiles on it. The Mac's Dock floats; Agora's belongs to the screen's edge, and
	 * that is a difference of shape, not of colour. */
	[[NSColor colorWithCalibratedRed:0.06 green:0.07 blue:0.08 alpha:0.45] setFill];
	[NSBezierPath fillRect:[self bounds]];

	for (i = 0; i < shown; i++) {
		NSRunningApplication *application = [_applications objectAtIndex:i];
		NSRect tile = DockTileRect([self bounds], _orientation, i, DockDefaultMetrics);
		NSImage *icon = [application icon];

		if (icon != nil) {
			[icon drawInRect:tile];
		} else {
			/* NO BUNDLE, NO ICON: a muted rounded square rather than nothing, so the tile is still a target a
			 * person can see and click. */
			NSBezierPath *placeholder = [NSBezierPath bezierPathWithRoundedRect:tile xRadius:9.0 yRadius:9.0];

			[[NSColor colorWithCalibratedRed:0.35 green:0.38 blue:0.42 alpha:1.0] setFill];
			[placeholder fill];
		}
		[self drawBadgeForApplication:application inTile:tile];
		if (application == _active) {
			/* THE DOT ON THE INNER SIDE: right of the icon on a left dock, left of it on a right dock. */
			CGFloat x = (_orientation == DockOrientationRight)
					    ? tile.origin.x - DOCK_INDICATOR_GAP - DOCK_INDICATOR_SIZE
					    : tile.origin.x + tile.size.width + DOCK_INDICATOR_GAP;
			NSRect dot = NSMakeRect(x, NSMidY(tile) - (DOCK_INDICATOR_SIZE / 2.0),
						DOCK_INDICATOR_SIZE, DOCK_INDICATOR_SIZE);
			NSBezierPath *indicator = [NSBezierPath bezierPathWithOvalInRect:dot];

			[[NSColor colorWithCalibratedRed:0.98 green:0.98 blue:0.98 alpha:0.95] setFill];
			[indicator fill];
		}
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
