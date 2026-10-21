/*
 * DockView.h — the strip's drawing and its hit test.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * The view owns NO model: it is handed the applications to draw and it draws them, and a click is reported as an
 * INDEX rather than an application, so the controller stays the only place that knows what a tile means. That split
 * is what lets the layout be tested without a view and the view be tested without a compositor.
 */
#ifndef DOCK_VIEW_H
#define DOCK_VIEW_H

#import <AppKit/NSView.h>

#import "DockLayout.h"

@class NSArray;
@class NSRunningApplication;

@interface DockView : NSView
{
@private
	NSArray *_applications;			/* NSRunningApplication, in the order the workspace gave them */
	NSRunningApplication *_active;		/* the one with the keyboard, marked with the indicator */
	DockOrientation _orientation;
	NSImage *_trashIcon;			/* resolved once from the trash directory */
	id _controller;				/* NOT retained: the controller owns this view */
}

- (void)setApplications:(NSArray *)applications;
- (void)setActiveApplication:(NSRunningApplication *)application;
- (void)setOrientation:(DockOrientation)orientation;
- (void)setController:(id)controller;

/* WHICH TILE A POINT IS OVER: an application index, the trash, or nothing. The view's own hit test, which is why
 * the click does not have to recompute the layout in the controller. */
typedef enum {
	DockHitNone = -1,
	DockHitTrash = -2
} DockHit;

- (NSInteger)hitTestTileAtPoint:(NSPoint)point;

@end

#endif /* DOCK_VIEW_H */
