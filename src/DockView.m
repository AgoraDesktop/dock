/*
 * DockView.m — the frosted strip, the icons, and the one dot that means "this one has the keyboard".
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * **THE BACKGROUND IS DRAWN BY THE VIEW AND NOT BY THE WINDOW**, because the window is transparent: the compositor
 * blends the strip over the wallpaper, and everything the view does not paint stays transparent. The rounded shelf
 * is inset from the strip's own edges so that the screen's edge shows a margin rather than a cut-off corner — the
 * same reason the Mac's Dock leaves air above its trash.
 *
 * **THE DOTTED INDICATOR IS THE ACTIVE APPLICATION, NOT "RUNNING".** Every tile in this Dock is a running
 * application (the list it draws comes from `NSWorkspace -runningApplications`), so a Mac-style running dot on all
 * of them would carry no information. The one thing that changes is which of them has the keyboard, and that is
 * what the dot marks.
 */
#import "DockView.h"

#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSRunningApplication.h>
#import <AppKit/NSWorkspace.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>

/* **WHAT THE VIEW ASKS ITS CONTROLLER FOR, DECLARED WHERE IT IS CALLED.** The view reports a tile INDEX and the
 * controller decides what that means; declaring the two messages here keeps the view free of the controller's
 * header and the controller free of the view's — the same informal-protocol shape `NSStatusItem.m` uses for the
 * window door it calls. */
@interface NSObject (DockViewActions)
- (void)activateTileAtIndex:(NSNumber *)index;
- (void)showMenuForTileAtIndex:(NSNumber *)index withEvent:(id)event;
@end

#define DOCK_SHELF_INSET	4.0
#define DOCK_SHELF_RADIUS	10.0
#define DOCK_INDICATOR_SIZE	5.0
#define DOCK_INDICATOR_GAP	6.0

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

/* THE TRASH'S ICON, WHICH IS THE THEME'S `user-trash` — asked of Icon Services through the directory rather than by
 * a name, because a place icon is keyed by the path it describes. Cached: it does not change while the Dock runs. */
- (NSImage *)trashIcon
{
	if (_trashIcon == nil) {
		NSString *home = NSHomeDirectory();

		if (home != nil) {
			_trashIcon = [[[NSWorkspace sharedWorkspace] iconForFile:[home stringByAppendingPathComponent:@".Trash"]]
				      retain];
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
	NSRect shelf = NSInsetRect([self bounds], DOCK_SHELF_INSET, DOCK_SHELF_INSET);
	NSBezierPath *background;
	NSUInteger count = [_applications count];
	NSUInteger fits = DockTilesThatFit([self bounds], DockDefaultMetrics);
	NSUInteger shown = (count < fits) ? count : fits;
	NSUInteger i;

	(void)dirtyRect;
	/* THE SHELF. A translucent near-black with the light grey line the platform's chrome uses: the Dock sits over
	 * a wallpaper, so it has to be both readable and see-through, and 0.55 alpha is the sample the Argentum palette
	 * uses for a raised surface over an arbitrary background. */
	background = [NSBezierPath bezierPathWithRoundedRect:shelf xRadius:DOCK_SHELF_RADIUS yRadius:DOCK_SHELF_RADIUS];
	[[NSColor colorWithCalibratedRed:0.09 green:0.09 blue:0.10 alpha:0.55] setFill];
	[background fill];
	[[NSColor colorWithCalibratedRed:1.0 green:1.0 blue:1.0 alpha:0.18] setStroke];
	[background setLineWidth:1.0];	[background stroke];

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
