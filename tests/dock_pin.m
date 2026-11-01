/*
 * dock_pin — dropping an application on the Dock: what the strip accepts, which slot it reports, and what it says to the
 * controller.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE DROP IS TWO QUESTIONS AND THIS MEASURES BOTH**: whether a drag is one the Dock will take (an application bundle
 * and nothing else), and WHERE it would put it — the slot under the pointer, which is the whole of "pin it where I
 * dropped it". The strip is drawn offscreen and the controller is a recording stand-in, so neither a compositor nor a
 * real Dock is needed: a real one needs a screen, and the arithmetic a drop is made of does not.
 *
 * A bundle on disk is what a drag from another application carries, so the fixtures are real bundles: one with an
 * `Info.plist` that declares an identifier, one with nothing inside, one spelled in capitals, and a plain folder that
 * must be refused.
 */
#import "DockController.h"
#import "DockLayout.h"
#import "DockTile.h"
#import "DockView.h"

#import <AppKit/NSApplication.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSGraphicsContext.h>

#include <stdio.h>
#include <sys/stat.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

/* ---- THE TWO STAND-INS -------------------------------------------------------- */

/* **A DRAG FROM ANOTHER APPLICATION, AS FAR AS THE STRIP IS CONCERNED**: a pasteboard of file names and a point. */
@interface AGPinDrag : NSObject <NSDraggingInfo>
{
	NSPasteboard *_pasteboard;
	NSPoint _location;
}
- (instancetype)initWithPaths:(NSArray *)paths at:(NSPoint)where;
@end

@implementation AGPinDrag

- (instancetype)initWithPaths:(NSArray *)paths at:(NSPoint)where
{
	static int sequence = 0;

	self = [super init];
	if (self != nil) {
		/* **ONE PASTEBOARD PER DRAG, BECAUSE A NAME IS THE STORE.** Two drags sharing a name share their contents — the
		 * second's file names replace the first's, which made the first drag read back as the second one's. */
		NSString *name = [NSString stringWithFormat:@"dock-pin-probe-%d", ++sequence];

		_pasteboard = [[NSPasteboard pasteboardWithName:name] retain];
		[_pasteboard clearContents];
		[_pasteboard declareTypes:[NSArray arrayWithObject:NSFilenamesPboardType] owner:nil];
		[_pasteboard setPropertyList:paths forType:NSFilenamesPboardType];
		_location = where;
	}
	return self;
}

- (void)dealloc
{
	[_pasteboard release];
	[super dealloc];
}

- (NSWindow *)draggingDestinationWindow { return nil; }
- (NSDragOperation)draggingSourceOperationMask { return NSDragOperationEvery; }
- (NSPoint)draggingLocation { return _location; }
- (NSPoint)draggedImageLocation { return _location; }
- (NSImage *)draggedImage { return nil; }
- (NSPasteboard *)draggingPasteboard { return _pasteboard; }
- (id)draggingSource { return nil; }
- (NSInteger)draggingSequenceNumber { return 1; }
- (void)slideDraggedImageTo:(NSPoint)screenPoint { (void)screenPoint; }
- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal { (void)isLocal; return NSDragOperationEvery; }

@end

/* **AND A CONTROLLER THAT ONLY RECORDS**, because what the strip is responsible for is WHICH applications and WHICH slot
 * it reports — the pinning itself is the controller's, and it needs a screen. */
@interface AGPinController : NSObject
{
@public
	NSArray *paths;
	NSInteger index;
	int calls;
	BOOL answer;
}
@end

@implementation AGPinController

- (BOOL)pinApplicationPaths:(NSArray *)somePaths atIndex:(NSInteger)someIndex
{
	[paths release];
	paths = [somePaths copy];
	index = someIndex;
	calls++;
	return answer;
}

- (void)cancelTileOrder {}
- (void)commitTileOrder {}
- (void)moveTileFromIndex:(NSNumber *)from toIndex:(NSNumber *)to { (void)from; (void)to; }
- (void)activateTileAtIndex:(NSNumber *)i { (void)i; }
- (void)showMenuForTileAtIndex:(NSNumber *)i withEvent:(id)e { (void)i; (void)e; }

- (void)dealloc
{
	[paths release];
	[super dealloc];
}

@end

/* ---- A BUNDLE ON DISK --------------------------------------------------------- */

static BOOL write_text(NSString *path, NSString *text)
{
	return [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

static NSString *make_bundle(NSString *root, NSString *name, NSString *identifier)
{
	NSString *bundle = [root stringByAppendingPathComponent:name];
	NSString *contents = [bundle stringByAppendingPathComponent:@"Contents"];
	NSString *manifest;

	[[NSFileManager defaultManager] createDirectoryAtPath:contents withIntermediateDirectories:YES
						   attributes:nil error:NULL];
	if (identifier == nil) {
		return bundle;
	}
	manifest = [NSString stringWithFormat:
		@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
		@"<plist version=\"1.0\"><dict>"
		@"<key>CFBundleIdentifier</key><string>%@</string>"
		@"<key>CFBundleName</key><string>%@</string>"
		@"<key>CFBundleExecutable</key><string>Probe</string>"
		@"<key>CFBundlePackageType</key><string>APPL</string>"
		@"</dict></plist>\n", identifier, [name stringByDeletingPathExtension]];
	write_text([contents stringByAppendingPathComponent:@"Info.plist"], manifest);
	return bundle;
}

int main(void)
{
	@autoreleasepool {
		NSString *root = [NSString stringWithFormat:@"/tmp/dock-pin-%d", (int)getpid()];
		NSFileManager *manager = [NSFileManager defaultManager];
		NSString *solid = nil;
		NSString *empty = nil;
		NSString *upper = nil;
		NSString *folder = nil;

		setvbuf(stdout, NULL, _IONBF, 0);
		(void)[[NSApplication sharedApplication] finishLaunching];
		[manager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL];

		solid = make_bundle(root, @"Probe.app", @"com.agora.dock-pin-probe");
		empty = make_bundle(root, @"Empty.app", nil);
		upper = make_bundle(root, @"Upper.APP", @"com.agora.dock-pin-upper");
		folder = [root stringByAppendingPathComponent:@"Plain Folder"];
		[manager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];

		/* 1. **WHAT A DRAG FROM ANOTHER APPLICATION MAY PIN.** The tile is built from the bundle's own declaration:
		 * `CFBundleIdentifier` is the pin's key, `CFBundleName` is what the tile is called, and the path is what it
		 * launches. A bundle with nothing inside has no identifier, so there would be nothing to write down; a plain
		 * folder is not an application at all; and a bundle spelled in capitals IS one. */
		{
			DockTile *tile = [DockTile tileWithApplicationBundleAtPath:solid];

			check(tile != nil, "an application bundle on disk makes a tile");
			check(tile != nil && [[tile identifier] isEqualToString:@"com.agora.dock-pin-probe"],
			      "whose identifier is the bundle's own");
			check(tile != nil && [[tile title] isEqualToString:@"Probe"],
			      "and whose name is the one the bundle declares");
			check(tile != nil && [[[tile bundleURL] path] isEqualToString:solid],
			      "with the file it was dropped from, for launching");
			check([tile isPinned] && [tile canBePinned], "a dropped bundle is a pin, ready to be written down");
			check([DockTile tileWithApplicationBundleAtPath:empty] == nil,
			      "a bundle that declares no identifier cannot be pinned");
			check([DockTile tileWithApplicationBundleAtPath:folder] == nil,
			      "and a plain folder is not an application");
			check([DockTile tileWithApplicationBundleAtPath:upper] != nil,
			      "a bundle spelled in capitals is one, as it is to every other door");
			check([DockTile tileWithApplicationBundleAtPath:[root stringByAppendingPathComponent:@"nope.app"]] == nil,
			      "and one that is not there is refused");
		}

		/* 2. **THE STRIP TAKES AN APPLICATION AND NOTHING ELSE.** The mask is what a person sees as the pointer's feedback
		 * before letting go, so a document dragged over the Dock must be a drag the Dock does not want. */
		{
			DockView *view = [[[DockView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 72.0, 400.0)] autorelease];
			AGPinController *controller = [[[AGPinController alloc] init] autorelease];
			AGPinDrag *appDrag = [[[AGPinDrag alloc] initWithPaths:
				[NSArray arrayWithObject:solid] at:NSMakePoint(36.0, 390.0)] autorelease];
			AGPinDrag *folderDrag = [[[AGPinDrag alloc] initWithPaths:
				[NSArray arrayWithObject:folder] at:NSMakePoint(36.0, 390.0)] autorelease];
			NSArray *tiles = [NSArray arrayWithObjects:
				[DockTile tileWithIdentifier:@"a.one" title:@"One" bundleURL:nil],
				[DockTile tileWithIdentifier:@"b.two" title:@"Two" bundleURL:nil], nil];

			[view setTiles:tiles];
			[view setController:controller];
			check([view draggingEntered:appDrag] == NSDragOperationCopy,
			      "an application dragged over the strip is a drag the Dock takes");
			/* **AND THE SLOT IS THE ONE UNDER THE POINTER.** A point above the first tile is slot 0 and one below the
			 * last is the last slot, so a drop on the strip's top puts the application first. */
			check([view externalDropIndex] == 0, "a drag over the top of the strip aims at the first slot");
			check([view draggingEntered:folderDrag] == NSDragOperationNone,
			      "and a folder is one it does not — which also takes the mark away");
			check([view externalDropIndex] == (NSInteger)DockHitNone,
			      "because a drag the Dock refuses is not one it is aiming at a slot");
			{
				NSRect first = DockTileRect([view bounds], DockOrientationRight, 0, DockDefaultMetrics);
				CGFloat pitch = DockDefaultMetrics.tile + DockDefaultMetrics.spacing;
				AGPinDrag *lower = [[[AGPinDrag alloc] initWithPaths:[NSArray arrayWithObject:solid]
								 at:NSMakePoint(36.0, NSMaxY(first) - pitch - 4.0)] autorelease];

				[view draggingEntered:lower];
				check([view externalDropIndex] == 1, "and one a tile lower aims at the second");
			}

			/* 3. **THE RELEASE IS WHAT PINS, AND IT SAYS WHICH SLOT.** The controller is asked once, with the application
			 * the view accepted and the slot it was aiming at; a drag the view refused is never reported. */
			check([view prepareForDragOperation:appDrag], "the release is prepared for a drag it accepted");
			check([view prepareForDragOperation:folderDrag] == NO, "and not for one it refused");
			controller->answer = YES;
			check([view performDragOperation:appDrag], "performing it answers what the controller did");
			check(controller->calls == 1 && controller->index == 1 && [controller->paths count] == 1
			      && [[controller->paths objectAtIndex:0] isEqualToString:solid],
			      "with the application's path and the slot the pointer was over");
			check([view externalDropIndex] == (NSInteger)DockHitNone,
			      "and the insertion mark is gone once the drop has happened");

			/* 4. **AND A DRAG THAT LEAVES TAKES ITS MARK WITH IT.** */
			[view draggingEntered:appDrag];
			check([view externalDropIndex] == 0, "the mark is back while a drag is over the strip");
			[view draggingExited:appDrag];
			check([view externalDropIndex] == (NSInteger)DockHitNone, "and gone when the drag leaves");
		}

		[manager removeItemAtPath:root error:NULL];
		/* 5. **THE TRASH TAKES ANY FILE, AND THROWS IT AWAY.** The trash is the one slot that is not an application: a
		 * document let go over it is recycled — the AppKit's own move, the same directory the Workspace's trash uses — and
		 * the drag's mask is accepted where the pin rule would have refused it. */
		{
			DockView *view = [[[DockView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 72.0, 400.0)] autorelease];
			NSRect trash = DockTrashRect([view bounds], DockOrientationRight, DockDefaultMetrics);
			NSPoint over = NSMakePoint(NSMidX(trash), NSMidY(trash));
			char scratch[64] = "/tmp/agora-dock-trash-XXXXXX";
			NSString *name = [NSString stringWithFormat:@"thrown-%d.txt", (int)getpid()];
			NSString *directory;
			NSString *victim;
			AGPinDrag *document;

			if (mkdtemp(scratch) == NULL) {
				printf("FAIL: could not make the trash fixture\n");
				goto done;
			}
			directory = [manager stringWithFileSystemRepresentation:scratch length:strlen(scratch)];
			victim = [directory stringByAppendingPathComponent:name];
			[manager createFileAtPath:victim contents:[NSData data] attributes:nil];
			document = [[[AGPinDrag alloc] initWithPaths:[NSArray arrayWithObject:victim] at:over] autorelease];
			[view setTiles:[NSArray array]];
			[view setController:nil];

			check([view draggingEntered:document] == NSDragOperationCopy,
			      "a document dragged over the TRASH is a drag the Dock takes");
			check([view cg_trashIsDropTarget], "and the trash is the tile it says it is over");
			[view draggingExited:document];
			check(![view cg_trashIsDropTarget], "which it stops saying when the drag leaves");
			(void)[view draggingEntered:document];
			check([view prepareForDragOperation:document], "the release is prepared for it");
			check([view performDragOperation:document], "and performing it moves the file to the trash");
			check(![manager fileExistsAtPath:victim], "the file is gone from where it was");
			{
				/* **WHERE A TRASH IS IS THE APPKIT'S RULE** — the home trash for an item on the home volume, a
				 * `.Trash-<uid>` on the item's own volume otherwise — and the fixture may sit on either. So the two
				 * candidates are asked, and exactly one of them holds the name. */
				NSArray *candidates = [NSArray arrayWithObjects:
					[NSHomeDirectory() stringByAppendingPathComponent:@".Trash"],
					[NSString stringWithFormat:@"/tmp/.Trash-%d", (int)getuid()], nil];
				NSUInteger i, found = 0;

				for (i = 0; i < [candidates count]; i++) {
					NSString *candidate = [[candidates objectAtIndex:i]
						stringByAppendingPathComponent:name];

					if ([manager fileExistsAtPath:candidate]) {
						found++;
						[manager removeItemAtPath:candidate error:NULL];
					}
				}
				check(found == 1, "and it is in a trash, once — the directory the Workspace's own trash uses");
			}
			check(![view cg_trashIsDropTarget], "with the mark gone once the drop has happened");
			[manager removeItemAtPath:directory error:NULL];
		}

	done:
		printf(s_failed == 0 ? "dock_pin: all checks passed\n" : "dock_pin: FAILURES\n");
	}
	return s_failed == 0 ? 0 : 1;
}
