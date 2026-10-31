/*
 * DockTile.h — one place on the strip: an application, running or not, and whether the user pinned it there.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * **A TILE OUTLIVES THE PROCESS IT NAMES, AND THAT IS THE WHOLE DIFFERENCE FROM A TILE THAT WAS
 * `NSRunningApplication`.** A pinned application has a place on the strip while it is quit, so the thing the strip
 * draws cannot be the running application — it is this: a bundle identifier, the name and file that identifier was
 * last seen under, and the running application when there is one. `DockView` draws tiles; only this class knows how
 * one gets its icon or how one survives a restart.
 *
 * THE NAME AND THE FILE ARE LAST SEEN RATHER THAN LOOKED UP, which is the one decision here worth stating. A pinned
 * application that is not running is not in the window list, so its name and its bundle have to come from somewhere:
 * they are written down when the tile is pinned (from the running application and its `-bundleURL`) and read back
 * from the defaults. Looking them up per refresh would be a Launch Services scan of the machine on every snapshot,
 * and the pinned list is exactly the cache that avoids it — `NSWorkspace -URLForApplicationWithBundleIdentifier:` is
 * asked only when a tile has no remembered file at all.
 */
#ifndef DOCK_TILE_H
#define DOCK_TILE_H

#import <Foundation/NSObject.h>

@class NSDictionary;
@class NSImage;
@class NSRunningApplication;
@class NSString;
@class NSURL;

@interface DockTile : NSObject
{
@private
	NSString *_identifier;		/* the bundle identifier: the Dock's name for the application, and the pin's key */
	NSString *_title;		/* what a tooltip would say, and what a pinned tile is called before it launches */
	NSURL *_bundleURL;		/* where the application was last seen, for launching and for the icon */
	NSRunningApplication *_application;	/* nil when the application is not running: a pin that is waiting */
	NSImage *_icon;			/* resolved once: an icon lookup per frame is a file read per frame */
	BOOL _pinned;
}

/* A TILE FOR AN APPLICATION THAT IS RUNNING, which is how every unpinned tile is made — and how a pinned one is
 * refreshed. The identifier comes from the application; a process that declares none still gets a tile (it can be
 * raised) but cannot be pinned, because there would be nothing to write down. */
+ (DockTile *)tileWithApplication:(NSRunningApplication *)application;

/* A TILE FROM THE PINNED LIST: what a previous run wrote down, with no application behind it until one appears. */
+ (DockTile *)tileWithIdentifier:(NSString *)identifier title:(NSString *)title bundleURL:(NSURL *)bundleURL;

/* **AND A TILE FROM AN APPLICATION ON DISK, WHICH IS WHAT A DRAG FROM ANOTHER APPLICATION CARRIES.** A dropped bundle has
 * no running application behind it — it may be one the Dock has never seen — so the identifier, the name and the file all
 * come from the bundle itself: `CFBundleIdentifier` for the pin's key, `CFBundleName` (and then the file's name) for what
 * the tile is called, and the path for launching and for the icon. Answers nil for a path that is not an application
 * bundle, which is what makes "what may be pinned" one question with one answer here rather than a rule each caller
 * repeats. */
+ (nullable DockTile *)tileWithApplicationBundleAtPath:(nullable NSString *)path;

- (NSString *)identifier;
- (NSString *)title;
- (NSURL *)bundleURL;

- (NSRunningApplication *)application;
/* **THE SNAPSHOT'S ANSWER, PUT ON A TILE THAT ALREADY EXISTS.** A pin is one tile for the life of the Dock: the
 * application arrives, quits and arrives again behind it, and the strip must not lose the tile's place meanwhile — so
 * the running application is SET here rather than being what the tile is. */
- (void)setApplication:(NSRunningApplication *)application;

- (BOOL)isRunning;
- (BOOL)isPinned;
- (void)setPinned:(BOOL)flag;
/* **WHETHER A GESTURE MAY PIN IT**, which is the same question as "does it have a name": an application that declares
 * no bundle identifier has nothing to write down, so its tile is drawn, raised, and left out of the pinned order. */
- (BOOL)canBePinned;

/* THE ICON THE STRIP DRAWS: the running application's, or the bundle's from disk, or nil for a placeholder. Resolved
 * once and kept. */
- (NSImage *)icon;

/* **THE TWO HALVES OF PERSISTENCE**, so the shape written to the defaults is this class's business rather than the
 * controller's: a dictionary of strings (identifier, title, path), and a tile back from one. */
- (NSDictionary *)propertyListRepresentation;
+ (DockTile *)tileWithPropertyListRepresentation:(NSDictionary *)plist;

@end

#endif /* DOCK_TILE_H */
