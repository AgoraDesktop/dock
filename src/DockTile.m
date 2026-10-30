/*
 * DockTile.m — a place on the strip: the application's name, file and icon, and the running process when there is one.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * **NOTHING HERE TALKS TO THE WINDOW SERVER, AND THAT IS DELIBERATE.** A tile is a value: it is made from a running
 * application or from a stored dictionary, it answers what the strip draws, and the controller decides what a click
 * on it means. `tests/dock_order.m` builds tiles from dictionaries with no compositor at all.
 */
#import "DockTile.h"

#import <AppKit/NSImage.h>
#import <AppKit/NSRunningApplication.h>
#import <AppKit/NSWorkspace.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>

/* THE THREE KEYS THE PINNED LIST IS WRITTEN UNDER, named once because they are a FILE FORMAT: a defaults plist that
 * outlives this build. Their spelling is the Dock's, not an application's. */
static NSString *const DockTileIdentifierKey = @"identifier";
static NSString *const DockTileTitleKey = @"title";
static NSString *const DockTilePathKey = @"path";

@implementation DockTile

+ (DockTile *)tileWithApplication:(NSRunningApplication *)application
{
	DockTile *tile;

	if (application == nil) {
		return nil;
	}
	tile = [[[self alloc] init] autorelease];
	tile->_identifier = [[application bundleIdentifier] copy];
	tile->_title = [[application localizedName] copy];
	if (tile->_title == nil) {
		tile->_title = [tile->_identifier copy];
	}
	tile->_bundleURL = [[application bundleURL] copy];
	tile->_application = [application retain];
	return tile;
}

+ (DockTile *)tileWithIdentifier:(NSString *)identifier title:(NSString *)title bundleURL:(NSURL *)bundleURL
{
	DockTile *tile;

	if ([identifier length] == 0) {
		return nil;
	}
	tile = [[[self alloc] init] autorelease];
	tile->_identifier = [identifier copy];
	tile->_title = ([title length] > 0) ? [title copy] : [identifier copy];
	tile->_bundleURL = [bundleURL copy];
	tile->_pinned = YES;
	return tile;
}

- (void)dealloc
{
	[_identifier release];
	[_title release];
	[_bundleURL release];
	[_application release];
	[_icon release];
	[super dealloc];
}

- (NSString *)identifier
{
	return _identifier;
}

- (NSString *)title
{
	return _title;
}

- (NSURL *)bundleURL
{
	return _bundleURL;
}

- (NSRunningApplication *)application
{
	return _application;
}

- (void)setApplication:(NSRunningApplication *)application
{
	if (_application == application) {
		return;
	}
	[application retain];
	[_application release];
	_application = application;
}

- (BOOL)isRunning
{
	return _application != nil;
}

- (BOOL)isPinned
{
	return _pinned;
}

- (void)setPinned:(BOOL)flag
{
	_pinned = flag ? YES : NO;
}

- (BOOL)canBePinned
{
	return [_identifier length] > 0;
}

/* **THE RUNNING APPLICATION'S ICON, OR THE BUNDLE'S FROM DISK, IN THAT ORDER.** A pinned application is asked for its
 * icon the same way every frame otherwise, so the answer is kept: `NSWorkspace -iconForFile:` reads and rasterises a
 * file, and a drag repaints the strip on every step. A tile with neither — a process with no bundle on disk — answers
 * nil and the view draws its placeholder, which is what it did before there were pins. */
- (NSImage *)icon
{
	NSString *path;

	if (_icon != nil) {
		return _icon;
	}
	if (_application != nil) {
		_icon = [[_application icon] retain];
		if (_icon != nil) {
			return _icon;
		}
	}
	/* THE REMEMBERED FILE, IF IT IS STILL THERE. */
	path = [_bundleURL path];
	if (path != nil && ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
		path = nil;
	}
	if (path == nil && [_identifier length] > 0) {
		/* **AND ONLY WHEN THERE IS NO USABLE FILE DOES LAUNCH SERVICES GET ASKED.** A pin written by an older run, or
		 * one whose bundle has moved, is resolved by identifier ONCE; asking per frame would be a directory scan per
		 * frame, and asking at all is the exception rather than the rule. */
		NSURL *found = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:_identifier];

		if (found != nil) {
			[_bundleURL release];
			_bundleURL = [found copy];
			path = [found path];
		}
	}
	if (path != nil) {
		_icon = [[[NSWorkspace sharedWorkspace] iconForFile:path] retain];
	}
	return _icon;
}

- (NSDictionary *)propertyListRepresentation
{
	NSMutableDictionary *plist = [NSMutableDictionary dictionary];
	NSString *path = [_bundleURL path];

	if ([_identifier length] > 0) {
		[plist setObject:_identifier forKey:DockTileIdentifierKey];
	}
	if ([_title length] > 0) {
		[plist setObject:_title forKey:DockTileTitleKey];
	}
	if ([path length] > 0) {
		[plist setObject:path forKey:DockTilePathKey];
	}
	return plist;
}

+ (DockTile *)tileWithPropertyListRepresentation:(NSDictionary *)plist
{
	id identifier;
	id title;
	id path;
	NSURL *url = nil;

	if (![plist isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	identifier = [plist objectForKey:DockTileIdentifierKey];
	title = [plist objectForKey:DockTileTitleKey];
	path = [plist objectForKey:DockTilePathKey];
	if (![identifier isKindOfClass:[NSString class]]) {
		return nil;
	}
	if ([path isKindOfClass:[NSString class]] && [path length] > 0) {
		url = [NSURL fileURLWithPath:path];
	}
	return [self tileWithIdentifier:identifier
				 title:([title isKindOfClass:[NSString class]] ? title : nil)
			     bundleURL:url];
}

@end
