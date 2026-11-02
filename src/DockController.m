/*
 * DockController.m — the strip, the tiles, and what a click, a menu or a drag means.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * **THE WINDOW'S FRAME IS THE STRIP AND THE RESERVATION IS THE SAME NUMBER.** `DockStripRect` says where the strip
 * is — flush with the side, ending at the menu bar — and `-cg_setReservedEdge:amount:` tells the window server that
 * the same width is furniture, so `NSScreen -visibleFrame` shrinks by it and no maximised window runs under the
 * Dock. Two statements of one number, made together, which is why they live in one method.
 *
 * **AND IT NEVER TAKES THE KEYBOARD.** Two halves, both stated: the Accessory activation policy (so the Dock has no
 * menu bar of its own) and `-cg_setActivatable:NO` on the window (`agora_window.set_activatable`), so a click on a
 * tile reaches the Dock's view without making the Dock the active application. Without the second half the menu bar
 * followed the click and the desktop was left with no bar at all — MEASURED, and the reason the door exists.
 *
 * **WHAT THE STRIP SHOWS IS TWO LISTS, AND THE ORDER IS `DockOrder`'S.** The PINNED tiles — the ones a person put
 * there, which are the ones written to the defaults — come first in their own order; the running applications that
 * nobody pinned follow, in the order the workspace named them. A tile is a `DockTile` rather than a running
 * application, because a pinned tile is the place an application comes back to and it has to exist while the
 * application does not.
 */
#import "DockController.h"

#import "DockOrder.h"
#import "DockTile.h"
#import "DockView.h"

#import <AppKit/NSApplication.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSDockMenu.h>
#import <AppKit/NSDockTile.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSRunningApplication.h>
#import <AppKit/platform/AGWindowServer.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSView.h>
#import <AppKit/NSStatusBar.h>
#import <AppKit/NSWorkspace.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSString.h>
#import <Foundation/NSUserDefaults.h>

#include <stdio.h>
#include <stdlib.h>

/* **THE ONE THING THE DOCK WRITES DOWN**, and it is a file format: an array of dictionaries, one per pinned tile, in
 * the user's order (`DockTile -propertyListRepresentation` says what is in each). The key is the Dock's, not an
 * application's, and it lives in this application's own defaults domain. */
static NSString *const DockPinnedApplicationsKey = @"DockPinnedApplications";

@implementation DockController

- (id)initWithOrientation:(DockOrientation)orientation
{
	if ((self = [super init]) != nil) {
		NSScreen *screen = [NSScreen mainScreen];
		NSRect screenFrame = [screen frame];
		CGFloat menuBar = [[NSStatusBar systemStatusBar] thickness];
		NSRect strip;

		_orientation = orientation;
		_metrics = DockDefaultMetrics;
		_tiles = [[NSArray alloc] init];
		_pinned = [[NSMutableArray alloc] init];
		/* **THE PINS ARE WRITTEN TO THIS APPLICATION'S OWN DOMAIN.** `+standardUserDefaults` answers the GLOBAL domain
		 * in this tier until the app domain follows the bundle (its own header says so), and a pinned list is not a
		 * thing to share with every application on the machine. The suite name is the bundle identifier, which is also
		 * the file's name once the app domain does follow it — so this is the same place, asked for early. */
		{
			NSString *domain = [[NSBundle mainBundle] bundleIdentifier];

			_defaults = [[NSUserDefaults alloc] initWithSuiteName:
				([domain length] > 0) ? domain : @"io.github.agoradesktop.dock"];
		}
		if (screenFrame.size.width <= 0.0 || screenFrame.size.height <= 0.0) {
			fprintf(stderr, "dock: no screen to sit on\n");
			[self release];
			return nil;
		}
		if (menuBar <= 0.0) {
			menuBar = 24.0;	/* a compositor that does not answer: the bar's own height, once */
		}
		strip = DockStripRect(screenFrame, menuBar, _orientation, _metrics);

		_window = [[NSWindow alloc] initWithContentRect:strip
						      styleMask:NSBorderlessWindowMask
							backing:NSBackingStoreBuffered
							  defer:NO];
		/* **TRANSPARENT, AND SAID BEFORE THE WINDOW IS SHOWN.** The seam chooses the buffer's format from
		 * `-isOpaque` when the window is made, so this order is the difference between a translucent band and a
		 * black rectangle. */
		[_window setOpaque:NO];
		[_window setBackgroundColor:[NSColor clearColor]];
		[_window setLevel:NSDockWindowLevel];
		[_window setReleasedWhenClosed:NO];
		/* NOT IN THE WINDOW MENU, NOT IN EXPOSÉ, AND NOT MOVED BY EITHER: the Dock is furniture. */
		[_window setCollectionBehavior:(NSWindowCollectionBehaviorStationary | NSWindowCollectionBehaviorIgnoresCycle)];
		/* **AND A CLICK ON IT NEVER MAKES THE DOCK THE ACTIVE APPLICATION.** Without this, clicking a tile gives
		 * the DOCK the keyboard, the menu bar follows it, and the desktop is left with no bar at all — MEASURED,
		 * which is why the door exists. The pointer still reaches the Dock; only the keyboard and the bar stay put. */
		[_window cg_setActivatable:NO];

		_view = [[DockView alloc] initWithFrame:NSMakeRect(0.0, 0.0, strip.size.width, strip.size.height)];
		[_view setOrientation:_orientation];
		[_view setController:self];
		[_window setContentView:_view];
		[_window orderFront:nil];

		/* **AND THE SCREEN IS TOLD THE STRIP IS TAKEN.** This is `agora_window.set_reserved` through the AppKit's
		 * Agora-owned door: right-edge furniture reserves the right edge, left-edge furniture the left, and every
		 * application's `-visibleFrame` shrinks by it from here on. */
		[_window cg_setReservedEdge:(_orientation == DockOrientationRight ? NSMaxXEdge : NSMinXEdge)
				     amount:_metrics.width];

		[[NSNotificationCenter defaultCenter] addObserver:self
							 selector:@selector(applicationsChanged:)
							     name:NSWorkspaceDidLaunchApplicationNotification
							   object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self
							 selector:@selector(applicationsChanged:)
							     name:NSWorkspaceDidTerminateApplicationNotification
							   object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self
							 selector:@selector(applicationsChanged:)
							     name:NSWorkspaceDidActivateApplicationNotification
							   object:nil];
		[self loadPinnedTiles];
		[self refresh];
		/* **THE LINE DOES NOT COUNT APPLICATIONS, BECAUSE AT THIS MOMENT THERE CANNOT BE ANY.** The list is a
		 * Wayland snapshot: `-runningApplications` asks for it, and the answer arrives on a later loop pass, so a
		 * count read here is always zero however many applications are running — MEASURED as `0 application(s)` in
		 * a session where Workspace was on the screen, which reads as a bug and is only the ask preceding the
		 * answer. The real count is a snapshot's to report; `AGORA_DOCK_DIAG=1` prints it after every one. */
		fprintf(stderr, "dock: %s, strip %.0fx%.0f at (%.0f,%.0f), %lu pinned\n",
			_orientation == DockOrientationRight ? "right" : "left",
			(double)strip.size.width, (double)strip.size.height, (double)strip.origin.x,
			(double)strip.origin.y, (unsigned long)[_pinned count]);
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_tiles release];
	[_pinned release];
	[_defaults release];
	[_menuTile release];
	[_draggingIdentifier release];
	[_orderBeforeDrag release];
	[_view release];
	[_window release];
	[super dealloc];
}

- (DockOrientation)orientation
{
	return _orientation;
}

- (NSRect)stripRect
{
	return [_window frame];
}

/* ---------------------------------------------------------------------------------------------------
 * the model: running applications, pinned tiles, and the one order the two make
 * --------------------------------------------------------------------------------------------------- */

/* **THE DOCK IS NOT IN ITS OWN LIST.** Its window declares the Dock's bundle identifier like any application's, so
 * the workspace reports it; a Dock that drew a tile for itself would be a tile that does nothing. The filter is by
 * identifier and not by object, because a relaunch makes a new object with the same name. */
- (NSArray *)applicationsExcludingSelf:(NSArray *)all
{
	NSMutableArray *kept = [NSMutableArray array];
	NSString *selfIdentifier = [[NSBundle mainBundle] bundleIdentifier];
	NSUInteger i;

	for (i = 0; i < [all count]; i++) {
		NSRunningApplication *application = [all objectAtIndex:i];

		if (selfIdentifier != nil && [[application bundleIdentifier] isEqualToString:selfIdentifier]) {
			continue;
		}
		[kept addObject:application];
	}
	return kept;
}

/* **THE PINNED LIST IS READ ONCE, AT START**, because it is the Dock's own property and nothing else in the process
 * changes it. A tile from a previous run has no application behind it: `-setApplication:` is what puts one there
 * when the snapshot names it, and that is also what lights its dot. */
- (void)loadPinnedTiles
{
	NSArray *stored = [_defaults arrayForKey:DockPinnedApplicationsKey];
	NSUInteger i;

	[_pinned release];
	_pinned = [[NSMutableArray alloc] init];
	for (i = 0; i < [stored count]; i++) {
		DockTile *tile = [DockTile tileWithPropertyListRepresentation:[stored objectAtIndex:i]];

		if (tile != nil) {
			[_pinned addObject:tile];
		}
	}
	[self ensureDesktopPinned];
}

/* AND WRITTEN WHENEVER IT CHANGES — a pin, an unpin, the release of a drag. Every write reaches the disk before
 * `-setObject:forKey:` returns (see NSUserDefaults' own note), so there is no `-synchronize` to wait for.
 *
 * **AND A STORE THAT CANNOT BE WRITTEN COSTS THE PINS THEIR NEXT LAUNCH, NOT THE DOCK ITS SESSION.** The defaults store
 * lives under the installation's configuration root (`AGORA_CONFIG_ROOT`), and a development machine that has never set
 * one writes `<home>/Configuration` under the host's own home directory — `/home/<name>` on Linux and the BSDs, which
 * an unprivileged process cannot create for another account. `-setObject:forKey:` RAISES there rather than answering
 * NO, and an exception thrown out of a menu row's action would take the Dock with it, so this is the one place in the
 * Dock that catches: the pins stay in memory and in the strip, the line says why they will not survive a relaunch, and
 * nothing else is affected. */
- (void)writePinnedTiles
{
	NSMutableArray *plists = [NSMutableArray array];
	NSUInteger i;

	for (i = 0; i < [_pinned count]; i++) {
		[plists addObject:[[_pinned objectAtIndex:i] propertyListRepresentation]];
	}
	@try {
		[_defaults setObject:plists forKey:DockPinnedApplicationsKey];
	} @catch (id exception) {
		/* ONCE PER PROCESS, AND SAID ONCE: a person who pins six applications should not get six copies of this. */
		static BOOL reported = NO;

		if (!reported) {
			reported = YES;
			fprintf(stderr, "dock: the pinned list cannot be written (%s) — it will last as long as this Dock "
					"does; set AGORA_CONFIG_ROOT to a writable directory to keep it\n",
				[[exception description] UTF8String]);
		}
	}
}

/* **THE DESKTOP'S TILE, MADE FROM LAUNCH SERVICES BECAUSE THAT IS THE ONLY NAME IT HAS WHEN IT IS NOT RUNNING.** A
 * pinned tile is written down with its file; the desktop's may not be there at all on a first launch, and its bundle
 * lives in a build tree in a development session (`AGORA_APPLICATIONS` is what tells Launch Services where). The name
 * comes from the bundle, and the tile falls back to the identifier's last component when nothing resolves — a Dock
 * that says "workspace" is still better than one with no desktop in it. */
- (DockTile *)desktopTile
{
	NSURL *url = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:DockDesktopIdentifier];
	NSString *title = nil;

	if (url != nil) {
		NSBundle *bundle = [NSBundle bundleWithPath:[url path]];

		title = [bundle objectForInfoDictionaryKey:@"CFBundleName"];
	}
	if ([title length] == 0) {
		title = @"Workspace";
	}
	return [DockTile tileWithIdentifier:DockDesktopIdentifier title:title bundleURL:url];
}

- (BOOL)isDesktopTile:(DockTile *)tile
{
	return [[tile identifier] isEqualToString:DockDesktopIdentifier];
}

/* **AND IT IS ALWAYS PINNED AND ALWAYS FIRST.** `DockOrder` keeps it at the top of the list it is given; this keeps it
 * IN the list, which is the half a hand-edited defaults file (or a build from before the desktop was special) can get
 * wrong. Called wherever the pinned list is loaded or rebuilt, which is the only way it can change. */
- (void)ensureDesktopPinned
{
	NSUInteger i;
	DockTile *desktop = nil;

	for (i = 0; i < [_pinned count]; i++) {
		if ([self isDesktopTile:[_pinned objectAtIndex:i]]) {
			desktop = [_pinned objectAtIndex:i];
			[desktop retain];
			[_pinned removeObjectAtIndex:i];
			break;
		}
	}
	if (desktop == nil) {
		desktop = [[self desktopTile] retain];
	}
	if (desktop != nil) {
		[desktop setPinned:YES];
		[_pinned insertObject:desktop atIndex:0];
		[desktop release];
	}
}

- (NSArray *)pinnedIdentifiers
{
	NSMutableArray *identifiers = [NSMutableArray array];
	NSUInteger i;

	for (i = 0; i < [_pinned count]; i++) {
		[identifiers addObject:[[_pinned objectAtIndex:i] identifier]];
	}
	return identifiers;
}

/* **THE TILE THE DOCK ALREADY HAS FOR AN IDENTIFIER**, which is what keeps a refresh from throwing away an icon it
 * has already resolved — and, more importantly, keeps a PINNED tile the same object across the application coming and
 * going. Answers a borrowed reference. */
- (DockTile *)tileWithIdentifier:(NSString *)identifier
{
	NSUInteger i;

	if ([identifier length] == 0) {
		return nil;
	}
	for (i = 0; i < [_tiles count]; i++) {
		DockTile *tile = [_tiles objectAtIndex:i];

		if ([[tile identifier] isEqualToString:identifier]) {
			return tile;
		}
	}
	for (i = 0; i < [_pinned count]; i++) {
		DockTile *tile = [_pinned objectAtIndex:i];

		if ([[tile identifier] isEqualToString:identifier]) {
			return tile;
		}
	}
	return nil;
}

/* **THE PINNED LIST BECOMES THE TILES NAMED**, in that order, reusing the tile the Dock already has where there is
 * one (so an icon and a name survive the edit) and marking every one of them pinned. */
- (void)setPinnedIdentifiers:(NSArray *)identifiers
{
	NSMutableArray *pinned = [NSMutableArray array];
	NSUInteger i;

	for (i = 0; i < [identifiers count]; i++) {
		NSString *identifier = [identifiers objectAtIndex:i];
		DockTile *tile = [self tileWithIdentifier:identifier];

		if (tile == nil) {
			/* a pin from the defaults whose file cannot be found: kept as a name, so the place is not silently
			 * dropped and an application that reappears takes it back */
			tile = [DockTile tileWithIdentifier:identifier title:nil bundleURL:nil];
		}
		if (tile == nil) {
			continue;
		}
		[tile setPinned:YES];
		[pinned addObject:tile];
	}
	[_pinned release];
	_pinned = [pinned mutableCopy];
	[self ensureDesktopPinned];
}

- (void)refresh
{
	NSArray *running = [self applicationsExcludingSelf:[[NSWorkspace sharedWorkspace] runningApplications]];
	NSMutableDictionary *runningByIdentifier = [NSMutableDictionary dictionary];
	NSMutableArray *runningIdentifiers = [NSMutableArray array];
	NSMutableArray *anonymous = [NSMutableArray array];
	NSMutableArray *tiles = [NSMutableArray array];
	NSArray *pinnedIdentifiers = [self pinnedIdentifiers];
	NSArray *order;
	NSUInteger i;

	/* **A RESTART ENDS BY STARTING THE DESKTOP AGAIN, AND ITS OWN SNAPSHOT IS THE PROOF THAT IT WENT.** `-terminate` is
	 * a REQUEST, so the Dock cannot relaunch on the back of having asked: it waits for a snapshot that no longer names
	 * the identifier, which is the same fact every other tile is drawn from. The launch is issued HERE, at the top of a
	 * refresh, so the refresh after it draws the new process's tile rather than the old one. */
	if (_restartPending) {
		BOOL gone = YES;

		for (i = 0; i < [running count]; i++) {
			if ([[[running objectAtIndex:i] bundleIdentifier] isEqualToString:DockDesktopIdentifier]) {
				gone = NO;
				break;
			}
		}
		if (gone) {
			_restartPending = NO;
			if (getenv("AGORA_DOCK_DIAG") != NULL) {
				fprintf(stderr, "dock: the desktop has gone; starting it again\n");
			}
			[self launchTile:[self tileWithIdentifier:DockDesktopIdentifier]];
		}
	}
	/* A LAUNCH INTERRUPTS A DRAG RATHER THAN BEING REORDERED BY IT: the snapshot is the truth about which
	 * applications exist, and a half-finished drag is not a truth about anything. The order a cancelled drag goes
	 * back to is dropped here for the same reason. */
	if (_draggingIdentifier != nil) {
		[_draggingIdentifier release];
		_draggingIdentifier = nil;
		[_orderBeforeDrag release];
		_orderBeforeDrag = nil;
	}
	for (i = 0; i < [running count]; i++) {
		NSRunningApplication *application = [running objectAtIndex:i];
		NSString *identifier = [application bundleIdentifier];

		if ([identifier length] == 0) {
			/* **AN APPLICATION THAT NAMES NO BUNDLE IS STILL A WINDOW TO RAISE.** It cannot be pinned (there would be
			 * nothing to write down) and it has no place in an order that is written by identifier, so it comes AFTER
			 * the ordered tiles, one tile per process. The wallpaper client that used to appear here went away with
			 * `--no-app-id`; a test binary or a raw client is what is left. */
			[anonymous addObject:application];
			continue;
		}
		[runningByIdentifier setObject:application forKey:identifier];
		[runningIdentifiers addObject:identifier];
	}
	order = DockOrderIdentifiers(pinnedIdentifiers, runningIdentifiers);
	for (i = 0; i < [order count]; i++) {
		NSString *identifier = [order objectAtIndex:i];
		NSRunningApplication *application = [runningByIdentifier objectForKey:identifier];
		DockTile *tile = [self tileWithIdentifier:identifier];

		if (tile == nil) {
			tile = [DockTile tileWithApplication:application];
		}
		if (tile == nil) {
			continue;
		}
		[tile setApplication:application];	/* nil when the application has quit: the dot goes dark, the place stays */
		[tile setPinned:[pinnedIdentifiers containsObject:identifier]];
		[tiles addObject:tile];
	}
	for (i = 0; i < [anonymous count]; i++) {
		DockTile *tile = [DockTile tileWithApplication:[anonymous objectAtIndex:i]];

		if (tile != nil) {
			[tiles addObject:tile];
		}
	}
	[_tiles release];
	_tiles = [tiles copy];
	[_view setTiles:_tiles];
	/* **THE BADGES, ASKED ONCE PER SNAPSHOT AND HANDED OVER WITH THE TILES.** `NSDockTile` answers what the
	 * running applications published (the Dock's half of the class), and an empty answer — no compositor, nothing
	 * published — is the ordinary case rather than an error. A pinned tile that is not running has no application to
	 * publish one, so its badge is simply absent. */
	[_view setBadgeLabels:[NSDockTile badgeLabelsByApplicationIdentifier]];
	/* **A TRACE, BECAUSE A DOCK IS HARD TO LOOK AT FROM A TEST.** `AGORA_DOCK_DIAG=1` prints what the strip
	 * believes after every snapshot — the same shape the AppKit's own `APPKIT_*_DIAG` switches have, and what
	 * `demo/` and a bug report are read from. A `*` is a running application and a `+` is a pin. */
	if (getenv("AGORA_DOCK_DIAG") != NULL) {
		fprintf(stderr, "dock: %lu tile(s)", (unsigned long)[_tiles count]);
		for (i = 0; i < [_tiles count]; i++) {
			DockTile *tile = [_tiles objectAtIndex:i];

			fprintf(stderr, " %s%s%s", [[tile identifier] UTF8String],
				[tile isPinned] ? "+" : "", [tile isRunning] ? "*" : "");
		}
		fprintf(stderr, "\n");
	}
}

- (void)applicationsChanged:(id)notification
{
	/* **A RESTART'S SECOND HALF IS COMPLETED HERE, BECAUSE THIS IS THE ONE MOMENT THE FACT IS KNOWN.** `NSWorkspace`
	 * posts `DidTerminate` BEFORE it drops the application from `-runningApplications` — deliberately, so a handler can
	 * still read what went — which means a refresh inside that callback still sees the desktop as running. MEASURED: the
	 * relaunch never happened and the Dock waited for a snapshot that had already arrived, while its own tile still said
	 * "running" for a process that was gone. So the question "did the application I asked to go actually go" is
	 * answered by the NOTIFICATION's application rather than by the list. `-refresh` keeps the same test as a fallback:
	 * a notification this process missed still completes on the next snapshot, because a pending restart is a fact about
	 * the Dock and not about one callback. */
	if (_restartPending) {
		NSRunningApplication *gone = [[notification userInfo] objectForKey:NSWorkspaceApplicationKey];

		if (gone != nil && [[gone bundleIdentifier] isEqualToString:DockDesktopIdentifier]) {
			_restartPending = NO;
			if (getenv("AGORA_DOCK_DIAG") != NULL) {
				fprintf(stderr, "dock: the desktop has gone; starting it again\n");
			}
			[self launchTile:[self tileWithIdentifier:DockDesktopIdentifier]];
		}
	}
	[self refresh];
}

/* ---------------------------------------------------------------------------------------------------
 * what a click means
 * --------------------------------------------------------------------------------------------------- */

/* **THE TRASH'S CLICK: A WINDOW ON `~/.Trash`, WHICH IS THE FILE MANAGER'S WINDOW AND NOT THIS ONE'S.** The strip drew
 * the tile; what a trash IS belongs to Workspace (`WSTrash` owns the directory, the Put Back records and the empty), so
 * the click is a REQUEST and not an action: the running file manager is asked to open the path, through the same
 * compositor channel a Dock menu question uses, and a file manager that is not running is launched instead — it then
 * opens its desktop, and the trash window is one click away from there.
 *
 * MEASURED as the reason this is a request rather than `-openURL:`: opening a folder by URL resolves an application by
 * DOCUMENT TYPE, and this tier's Workspace declares none — and a second Workspace would be a second desktop. The
 * application that is already running is the one that has to be told. */
- (void)openTrash:(id)sender
{
	(void)sender;
	NSString *trash = [NSHomeDirectory() stringByAppendingPathComponent:@".Trash"];
	NSArray *running = [[NSWorkspace sharedWorkspace] runningApplications];
	NSRunningApplication *desktop = nil;
	NSUInteger i;

	for (i = 0; i < [running count]; i++) {
		NSRunningApplication *application = [running objectAtIndex:i];

		if ([[application bundleIdentifier] isEqualToString:DockDesktopIdentifier]) {
			desktop = application;
			break;
		}
	}
	if (desktop != nil) {
		/* **A WINDOW IS THE ADDRESS AND NOT THE SUBJECT**, exactly as a dock menu's is: any window of the application
		 * names it, and the frontmost is the honest choice. */
		NSArray *windows = [desktop cg_windowIDs];
		BOOL asked = NO;

		if ([windows count] > 0) {
			asked = (AGWindowServerOpenFile(AGWindowServerShared(), [[windows lastObject] unsignedIntValue],
							[trash UTF8String]) != 0);
		}
		if (getenv("AGORA_DOCK_DIAG") != NULL) {
			fprintf(stderr, "dock: trash click -> %s (%lu window(s))\n", asked ? "asked" : "refused",
				(unsigned long)[windows count]);
		}
		if (asked) {
			return;
		}
	}
	/* NOTHING TO ASK: the file manager is not running, so the click starts it — which is what a tile click does for
	 * every other application. */
	[self launchTile:[self tileWithIdentifier:DockDesktopIdentifier]];
}

/* **THE BIN'S MENU: EMPTY TRASH, A SEPARATOR, OPEN — the reference Dock's three, in its order.** It is the Dock's own
 * and not an application's, because a trash is not an application: there is nobody to ask for rows.
 *
 * **EMPTYING IS NOT UNDOABLE AND DOES NOT ASK.** `WSTrash` owns the recycle and the empty in the file manager, where a
 * conflict sheet and an undo stack live; the Dock has neither, so this deletes the directory's contents — the Put Back
 * records with them, since a record nothing points at is litter — and the strip draws the empty bin on its next tick.
 * Asking a modal question from a window that cannot take the keyboard (`set_activatable:NO`) is the one thing this tier
 * must not do here, so the question is not asked: the row is the row, and a trash can be refilled with one drag. */
- (NSMenu *)trashMenu
{
	NSMenu *menu = [[[NSMenu alloc] initWithTitle:@"Trash"] autorelease];
	NSMenuItem *empty = [[[NSMenuItem alloc] initWithTitle:@"Empty Trash"
						       action:@selector(emptyTrash:)
						keyEquivalent:@""] autorelease];
	NSMenuItem *open = [[[NSMenuItem alloc] initWithTitle:@"Open"
						      action:@selector(openTrash:)
					       keyEquivalent:@""] autorelease];

	[empty setTarget:self];
	[open setTarget:self];
	[menu addItem:empty];
	[menu addItem:[NSMenuItem separatorItem]];
	[menu addItem:open];
	return menu;
}

- (NSUInteger)cg_emptyTrashAtPath:(NSString *)path
{
	NSFileManager *files = [NSFileManager defaultManager];
	NSArray *entries = [files contentsOfDirectoryAtPath:path error:NULL];
	NSUInteger deleted = 0;
	NSUInteger i;

	for (i = 0; i < [entries count]; i++) {
		NSString *entry = [path stringByAppendingPathComponent:[entries objectAtIndex:i]];

		if ([files removeItemAtPath:entry error:NULL]) {
			deleted++;
		}
	}
	return deleted;
}

/* **THE ROW DOES NOT DO THE WORK ITSELF, IT ASKS FOR IT AFTER THE MENU.** A menu's action runs INSIDE the menu's own
 * tracking loop — `-rightMouseDown:` calls `[NSMenu popUpContextMenu:…]`, which pumps until the menu ends — so anything
 * the action does that touches windows, the application list or the strip happens while a menu session is up. That is
 * the shape of a stall: the session cannot end until the action returns, and the action cannot finish cleanly while the
 * session is up. The empty is therefore queued for the next turn of the run loop, which is after the menu has gone. */
- (void)emptyTrash:(id)sender
{
	(void)sender;
	[self performSelector:@selector(fn_emptyTrashNow) withObject:nil afterDelay:0.0];
}

- (void)fn_emptyTrashNow
{
	(void)[self cg_emptyTrashAtPath:[NSHomeDirectory() stringByAppendingPathComponent:@".Trash"]];
	[self refresh];
	[_view setNeedsDisplay:YES];
}

- (void)activateTileAtIndex:(NSNumber *)index
{
	NSUInteger i = (NSUInteger)[index integerValue];
	DockTile *tile;

	if (i >= [_tiles count]) {
		return;
	}
	tile = [_tiles objectAtIndex:i];
	if ([tile isRunning]) {
		/* **A CLICK ON A TILE IS `-activateWithOptions:`, WHICH IS RAISE AND KEYBOARD — OR A REQUEST FOR A WINDOW.**
		 * The application's windows come forward — all of them, in the order they were already in — and the frontmost
		 * takes the keyboard, which is what makes the menu bar change to the application the person just picked. An
		 * application whose windows are all furniture (Workspace with its desktop and no file window) has nothing to
		 * raise, and then the AppKit asks it to reopen and it opens a window. The Dock does not decide which of the
		 * two happened: a tile names an application, and what "bring it forward" means is the application's answer. */
		[[tile application] activateWithOptions:NSApplicationActivateAllWindows];
		return;
	}
	/* **A PIN WITH NOTHING BEHIND IT IS A LAUNCH**, and the click means the same thing either way: the application
	 * comes forward. */
	[self launchTile:tile];
}

/* **THE ONE LAUNCH PATH, BECAUSE A PIN'S CLICK AND THE DESKTOP'S RESTART MEAN THE SAME THING TO LAUNCH SERVICES.** The
 * file remembered with the tile is asked for first, because it is what the person pinned; a bundle that has moved asks
 * Launch Services by identifier, which is the only name the two sides share. The new process maps its window and takes
 * the keyboard the way every launch does — the Dock does not need to activate it afterwards, and could not: on the pass
 * after the spawn there is nothing to activate yet. */
- (void)launchTile:(DockTile *)tile
{
	NSURL *url = (tile != nil) ? [tile bundleURL] : nil;

	if (url == nil && [[tile identifier] length] > 0) {
		url = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:[tile identifier]];
	}
	if (url != nil) {
		[[NSWorkspace sharedWorkspace] openURL:url];
	}
}

/* **A DROP FROM ANOTHER APPLICATION IS THE OTHER WAY A TILE IS PINNED**, and it is the same statement the drag inside the
 * strip makes: this application belongs at this place. The slot is a position in the DISPLAYED strip, whose beginning is
 * the pinned list — so it is used directly as a position in that list, and a slot past the last shown tile (the pointer
 * over the trash, or below the strip) becomes the end of it, which is where a Dock puts a new tile.
 *
 * **THE TILE THE DOCK ALREADY HAS WINS**, so an application that is running and unpinned keeps its icon, its name and its
 * running dot when it is pinned; a bundle nobody has seen becomes a tile of its own, built from the bundle's own
 * declaration (see `DockTile`). The pinned list is then rebuilt through `-setPinnedIdentifiers:`, which is what applies
 * the desktop rule, and written down — a pin that did not survive the next launch would not be a pin. */
- (BOOL)pinApplicationPaths:(NSArray *)paths atIndex:(NSInteger)index
{
	NSMutableArray *identifiers = [NSMutableArray arrayWithArray:[self pinnedIdentifiers]];
	NSMutableArray *tiles = [NSMutableArray array];
	NSInteger at = (index < 0) ? (NSInteger)[identifiers count] : index;
	NSUInteger i;

	for (i = 0; i < [paths count]; i++) {
		id path = [paths objectAtIndex:i];
		DockTile *tile = nil;

		if (![path isKindOfClass:[NSString class]]) {
			continue;
		}
		{
			DockTile *dropped = [DockTile tileWithApplicationBundleAtPath:path];
			DockTile *existing;

			if (dropped == nil) {
				continue;
			}
			existing = [self tileWithIdentifier:[dropped identifier]];
			tile = (existing != nil) ? existing : dropped;
		}
		[tile setPinned:YES];
		/* A TILE THAT WAS ALREADY THE DOCK'S KEEPS ITS OWN FILE AND NAME; one built from the dropped bundle carries the
		 * path it came from, which is what the tile's launch and its icon are drawn from. */
		if (![_pinned containsObject:tile]) {
			NSUInteger slot = (at < 0) ? 0 : ((NSUInteger)at > [_pinned count] ? [_pinned count] : (NSUInteger)at);

			[_pinned insertObject:tile atIndex:slot];
		}
		identifiers = [NSMutableArray arrayWithArray:
				DockOrderInsertingIdentifier(identifiers, [tile identifier],
							     (at < 0) ? 0 : (NSUInteger)at)];
		[tiles addObject:tile];
		at++;
	}
	if ([tiles count] == 0) {
		return NO;
	}
	[self setPinnedIdentifiers:identifiers];
	[self writePinnedTiles];
	[self refresh];
	return YES;
}

/* ---------------------------------------------------------------------------------------------------
 * the drag: one step, the release, and the way back
 * --------------------------------------------------------------------------------------------------- */

- (void)moveTileFromIndex:(NSNumber *)from toIndex:(NSNumber *)to
{
	NSUInteger f = (NSUInteger)[from integerValue];
	NSUInteger t = (NSUInteger)[to integerValue];
	DockTile *tile;
	NSArray *moved;

	if (f >= [_tiles count] || t >= [_tiles count]) {
		return;
	}
	tile = [_tiles objectAtIndex:f];
	/* A TILE THAT CANNOT BE PINNED CANNOT BE DRAGGED EITHER: the drag's whole outcome is a written-down order, and
	 * there is no identifier to write. Its place after the ordered tiles is the only one it has. */
	if (![tile canBePinned]) {
		return;
	}
	/* AND THE DESKTOP HAS NOWHERE TO GO: it is the top of the strip by rule, so a drag of it would be undone by the
	 * next refresh — refusing it here is the honest answer rather than a tile that springs back. */
	if ([self isDesktopTile:tile]) {
		return;
	}
	if (_orderBeforeDrag == nil) {
		_orderBeforeDrag = [_tiles copy];
		[_draggingIdentifier release];
		_draggingIdentifier = [[tile identifier] copy];
	}
	moved = DockOrderMoving(_tiles, f, t);
	[_tiles release];
	_tiles = [moved copy];
	[_view setTiles:_tiles];
}

- (void)commitTileOrder
{
	NSMutableArray *displayed = [NSMutableArray array];
	NSArray *pinned;
	NSUInteger i;

	if (_draggingIdentifier == nil) {
		return;	/* nothing moved: a press that never became a drag never reaches here */
	}
	for (i = 0; i < [_tiles count]; i++) {
		[displayed addObject:[[_tiles objectAtIndex:i] identifier]];
	}
	pinned = DockOrderPinnedAfterMove([self pinnedIdentifiers], displayed, _draggingIdentifier);
	[self setPinnedIdentifiers:pinned];
	[self writePinnedTiles];
	[_draggingIdentifier release];
	_draggingIdentifier = nil;
	[_orderBeforeDrag release];
	_orderBeforeDrag = nil;
	/* AND THE STRIP IS REBUILT FROM THE LIST THAT WAS JUST WRITTEN, so what a person sees after the release is what
	 * the next launch will show. The pinned tiles are already in the dropped order, so the displayed order does not
	 * move — the running applications that were never pinned slide back to the end, which is the one visible cost of
	 * pinning by drag and is what the order rule says. */
	[self refresh];
}

- (void)cancelTileOrder
{
	NSArray *restored = [_orderBeforeDrag retain];

	[_draggingIdentifier release];
	_draggingIdentifier = nil;
	[_orderBeforeDrag release];
	_orderBeforeDrag = nil;
	if (restored != nil) {
		[_tiles release];
		_tiles = [restored copy];
		[_view setTiles:_tiles];
	}
	[restored release];
}

/* ---------------------------------------------------------------------------------------------------
 * what the menu means
 * --------------------------------------------------------------------------------------------------- */

- (void)showMenuForTileAtIndex:(NSNumber *)index withEvent:(id)event
{
	NSUInteger i = (NSUInteger)[index integerValue];
	DockTile *tile;
	NSMenu *menu;
	NSMenuItem *item;
	NSString *title;

	if (i >= [_tiles count]) {
		return;
	}
	tile = [_tiles objectAtIndex:i];
	[_menuTile release];
	_menuTile = [tile retain];

	/* **THE APPLICATION'S OWN ITEMS COME FIRST, AND THEY COME FROM IT.** A tile's menu is the application's answer to
	 * `-applicationDockMenu:` with the Dock's own rows under it — the Mac's arrangement, and the reason the two
	 * halves have to meet in ONE panel: an application cannot draw at the Dock's edge, and a Dock cannot know what an
	 * application's menu means. `NSDockMenu` asks (bounded), waits, and builds the rows; each carries the id the
	 * application gave it, which is what a pick sends back. A PINNED TILE THAT IS NOT RUNNING asks nobody: there is no
	 * window for the question to reach. */
	menu = ([tile isRunning] && [tile application] != nil)
		       ? [[NSDockMenu menuForApplication:[tile application]] retain]
		       : nil;
	if (menu == nil) {
		/* NO MENU IS STILL A MENU: the Dock's own rows, and nothing else. */
		menu = [[NSMenu alloc] initWithTitle:@""];
	} else {
		[self bindApplicationItemsInMenu:menu];
		/* **AND THE DOCK DOES NOT RE-VALIDATE THE APPLICATION'S ROWS.** `-update`'s enabling walk would ask each
		 * item's target — which is this controller now — whether it answers the action, and that would enable
		 * every row the description marked disabled. The validation was made in the application, where the real
		 * targets are, so the Dock's job is to draw what it was told. */
		[menu setAutoenablesItems:NO];
		/* A SEPARATOR ONLY WHEN THERE IS SOMETHING ABOVE IT TO SEPARATE — an empty application menu followed by a
		 * rule would be a menu that starts with one. */
		if ([menu numberOfItems] > 0) {
			[menu addItem:[NSMenuItem separatorItem]];
		}
	}

	if ([self isDesktopTile:tile]) {
		/* **THE DESKTOP'S MENU IS ONE ROW, AND IT IS NOT QUIT.** Workspace's tile cannot be pinned or unpinned (there
		 * is nothing to decide: it is always there and always first), and quitting it would leave the desktop without
		 * the thing the Dock is furniture for. Replacing it is the repair a person actually wants — the Dock asks it to
		 * go and starts it again as soon as its own snapshot says it has. */
		if ([menu numberOfItems] > 0) {
			[menu addItem:[NSMenuItem separatorItem]];
		}
		title = [NSString stringWithFormat:@"Restart %@", [tile title]];
		item = [[NSMenuItem alloc] initWithTitle:title action:@selector(restartFromMenu:) keyEquivalent:@""];
		[item setTarget:self];
		[menu addItem:item];
		[item release];
	} else {
		/* **THE PIN ROW, IN THE MAC'S OWN WORDS.** `Keep in Dock` / `Remove from Dock` is what a 10.6 Dock said for
		 * the two halves of this, and the vocabulary inside this tree is "pinned" — the row is the gesture, the
		 * defaults key is the fact. A process with no bundle identifier has nothing to write down, so its row is
		 * disabled rather than absent: the menu keeps its shape and says why. */
		title = [tile isPinned] ? @"Remove from Dock" : @"Keep in Dock";
		item = [[NSMenuItem alloc] initWithTitle:title action:@selector(togglePinFromMenu:) keyEquivalent:@""];
		[item setTarget:self];
		[item setEnabled:[tile canBePinned]];
		[menu addItem:item];
		[item release];

		/* AND QUIT, WHICH ONLY A RUNNING APPLICATION CAN ANSWER. */
		if ([tile isRunning]) {
			[menu addItem:[NSMenuItem separatorItem]];
			title = [NSString stringWithFormat:@"Quit %@", [tile title]];
			item = [[NSMenuItem alloc] initWithTitle:title action:@selector(quitFromMenu:) keyEquivalent:@""];
			[item setTarget:self];
			[menu addItem:item];
			[item release];
		}
	}
	/* **AND THE CLICK THAT DISMISSES IT IS THE MENU'S, NOT THE WINDOW UNDER IT.** A menu is a pop-up: the click that
	 * ends one is not a click on whatever it landed over. Without something to catch that click it lands on the
	 * desktop, or on another application's window, and the window server gives THAT window the keyboard — so a person
	 * dismissing a Dock menu watches the menu bar change application. The catcher is an invisible, non-activatable
	 * window over the screen for exactly the length of the session (see `-showMenuCatcher`). */
	[self showMenuCatcher];
	[NSMenu popUpContextMenu:menu withEvent:event forView:_view];
	[_catcher orderOut:nil];
	[menu release];
}

/* **THE APPLICATION'S ROWS BECOME THE DOCK'S TO SEND, AND NOTHING ELSE ABOUT THEM CHANGES.** A row the description
 * gave an id is one the person may choose, so it gets this controller and one selector — the id travels in its
 * `-representedObject` — while a row that opens a submenu is recursed into and the submenu's own rows are bound the
 * same way. Separators and anything without an id are left exactly as they arrived. */
- (void)bindApplicationItemsInMenu:(NSMenu *)menu
{
	NSArray *items = [menu itemArray];
	NSUInteger i;

	for (i = 0; i < [items count]; i++) {
		NSMenuItem *menuItem = [items objectAtIndex:i];

		if ([menuItem submenu] != nil) {
			[self bindApplicationItemsInMenu:(NSMenu *)[menuItem submenu]];
			continue;
		}
		if ([menuItem representedObject] == nil) {
			continue;
		}
		[menuItem setTarget:self];
		[menuItem setAction:@selector(activateApplicationMenuItem:)];
	}
}

- (void)activateApplicationMenuItem:(id)sender
{
	NSNumber *identifier = [(NSMenuItem *)sender representedObject];

	if (_menuTile == nil || identifier == nil || [_menuTile application] == nil) {
		return;
	}
	/* **THE ID AND THE APPLICATION, AND NOTHING ELSE CROSSES.** What the row means — the action, the target,
	 * the state it changes — is the application's, and it sends it itself when the id comes home. */
	[NSDockMenu dispatchActionForItem:[identifier integerValue] toApplication:[_menuTile application]];
}

/* **THE ONE ROW THAT CHANGES THE DOCK'S SHAPE.** A tile that is pinned is removed from the pinned list; one that is
 * not is appended to it. A running application stays where it is either way — unpinned it is still a running
 * application, which is a tile at the end of the strip; quit it is gone, which is what "Remove from Dock" asks for. */
- (void)togglePinFromMenu:(id)sender
{
	NSArray *pinned;

	(void)sender;
	if (_menuTile == nil || ![_menuTile canBePinned]) {
		return;
	}
	if ([self isDesktopTile:_menuTile]) {
		return;	/* the row is not offered for the desktop, and the door refuses it if a caller asks anyway */
	}
	if ([_menuTile isPinned]) {
		pinned = DockOrderPinnedRemoving([self pinnedIdentifiers], [_menuTile identifier]);
	} else {
		pinned = DockOrderPinnedAdding([self pinnedIdentifiers], [_menuTile identifier]);
	}
	[self setPinnedIdentifiers:pinned];
	[self writePinnedTiles];
	[self refresh];
}

/* **THE DESKTOP'S ONE ROW: ASK IT TO GO, AND START IT AGAIN WHEN IT HAS.** The quit is a request (`-terminate`), so
 * what follows is not a `SIGKILL` and a spawn but a state machine with two facts in it: the request was made, and the
 * workspace's own snapshot no longer names it — see `-refresh`, which is where the second half runs. A desktop that is
 * not running has nothing to replace, so the row is a start. */
- (void)restartFromMenu:(id)sender
{
	(void)sender;
	if (_menuTile == nil) {
		return;
	}
	if (![_menuTile isRunning]) {
		[self launchTile:_menuTile];
		return;
	}
	_restartPending = YES;
	if (getenv("AGORA_DOCK_DIAG") != NULL) {
		fprintf(stderr, "dock: restart asked of %s; waiting for its snapshot to say it has gone\n",
			[[_menuTile identifier] UTF8String]);
	}
	[[_menuTile application] terminate];
}

/* **AN INVISIBLE WINDOW OVER THE SCREEN, FOR THE LENGTH OF A TILE'S MENU.** It is the click catcher described at the
 * call site: transparent, at `NSMainMenuWindowLevel - 1` (above the desktop, every ordinary window and the Dock's own
 * strip; below the menu bar and below the menu, which is at the pop-up level), and NON-ACTIVATABLE, so a press that
 * lands on it gives the keyboard to nobody. The menu's session pulls the application's events, sees a press addressed
 * to another window, and dismisses — which is `NSMenu`'s rule, not this class's. Made once and reused; a window that
 * is ordered out maps nothing. */
- (void)showMenuCatcher
{
	if (_catcher == nil) {
		NSRect frame = [[NSScreen mainScreen] frame];

		_catcher = [[NSWindow alloc] initWithContentRect:frame
						       styleMask:NSBorderlessWindowMask
							 backing:NSBackingStoreBuffered
							   defer:NO];
		[_catcher setOpaque:NO];
		[_catcher setBackgroundColor:[NSColor clearColor]];
		[_catcher setLevel:(NSInteger)NSMainMenuWindowLevel - 1];
		[_catcher setReleasedWhenClosed:NO];
		[_catcher setCollectionBehavior:(NSWindowCollectionBehaviorStationary | NSWindowCollectionBehaviorIgnoresCycle)];
		[_catcher cg_setActivatable:NO];
		[_catcher setContentView:[[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, frame.size.width,
										 frame.size.height)] autorelease]];
	}
	[_catcher orderFront:nil];
}

- (void)quitFromMenu:(id)sender
{
	(void)sender;
	/* **A REQUEST, NOT A KILL.** `-terminate` asks every window to close and the application decides; Force Quit
	 * is the session's, and there is no session yet. */
	[[_menuTile application] terminate];
}

@end
