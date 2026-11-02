/*
 * dock_trash — the bin's own menu, and what "empty" does to a directory.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE TRASH IS NOT A TILE WITH AN APPLICATION BEHIND IT.** Every other tile's menu comes from the application it names
 * (`-applicationDockMenu:`), so there is nobody to ask for the bin's rows: they are the Dock's own, and they are the
 * reference Dock's three — Empty Trash, a separator, Open. What each row does is the other half: `-openTrash:` is the
 * request a click on the tile already makes, and `-emptyTrash:` deletes what the directory holds, its Put Back records
 * with it.
 *
 * THE CONTROLLER IS MADE WITHOUT A STRIP, which is why this suite can run with no screen and no compositor: `-init`
 * leaves the window, the tiles and the defaults alone, and the two doors measured here touch none of them. The file work
 * is driven through `-cg_emptyTrashAtPath:`, so the trash that is emptied is the probe's and not the account's.
 */
#import "DockController.h"

#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <Foundation/Foundation.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) s_failed++;
}

static BOOL makeDirectory(NSString *path)
{
	return [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES
								  attributes:nil error:NULL];
}

static BOOL makeFile(NSString *path)
{
	return [[NSFileManager defaultManager] createFileAtPath:path contents:[NSData data] attributes:nil];
}

int main(void)
{
	NSString *root = [@"/tmp" stringByAppendingPathComponent:
		[NSString stringWithFormat:@"agora-dock-trash-%d", (int)getpid()]];
	DockController *controller;
	NSMenu *menu;
	NSArray *rows;

	setvbuf(stdout, NULL, _IONBF, 0);
	[[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
	check(makeDirectory(root), "the probe made its temporary tree");

	controller = [[DockController alloc] init];
	check(controller != nil, "a controller is made without a strip");

	/* ---- 1. THE ROWS, IN THE REFERENCE DOCK'S ORDER --------------------------------------- */
	menu = [controller trashMenu];
	rows = (menu != nil) ? [menu itemArray] : nil;
	check([rows count] == 3, "the bin's menu has three rows");
	if ([rows count] == 3) {
		check([[[rows objectAtIndex:0] title] isEqual:@"Empty Trash"],
		      "the first is Empty Trash");
		check([[rows objectAtIndex:0] action] == @selector(emptyTrash:)
		      && [[rows objectAtIndex:0] target] == controller,
		      "and it is the Dock's own command, aimed at the Dock");
		check([[rows objectAtIndex:1] isSeparatorItem], "the second is a separator");
		check([[[rows objectAtIndex:2] title] isEqual:@"Open"],
		      "the third is Open");
		check([[rows objectAtIndex:2] action] == @selector(openTrash:)
		      && [[rows objectAtIndex:2] target] == controller,
		      "which is the same request a click on the tile makes");
	}

	/* ---- 2. EMPTYING IS THE DIRECTORY'S CONTENTS, RECORDS AND ALL -------------------------- */
	{
		NSString *trash = [root stringByAppendingPathComponent:@".Trash"];
		NSString *putback = [trash stringByAppendingPathComponent:@".putback"];
		NSUInteger deleted;

		check(makeDirectory(putback), "a trash is made with its Put Back records beside it");
		check(makeFile([trash stringByAppendingPathComponent:@"one.txt"]), "and one item in it");
		check(makeFile([putback stringByAppendingPathComponent:@"one.txt.plist"]), "with its record");
		check(makeFile([trash stringByAppendingPathComponent:@"two.txt"]), "and a second item");

		deleted = [controller cg_emptyTrashAtPath:trash];
		check(deleted == 3, "emptying deletes everything the directory holds, the records with it");
		check(![[NSFileManager defaultManager] fileExistsAtPath:[trash stringByAppendingPathComponent:@"one.txt"]]
		      && ![[NSFileManager defaultManager] fileExistsAtPath:
				[putback stringByAppendingPathComponent:@"one.txt.plist"]],
		      "and a record nothing points at is gone too");
		check([[NSFileManager defaultManager] contentsOfDirectoryAtPath:trash error:NULL] != nil,
		      "while the trash directory itself is still there");

		/* AND AN EMPTY ONE IS NOT AN ERROR: nothing to delete is nothing to do. */
		check([controller cg_emptyTrashAtPath:trash] == 0, "emptying an empty trash deletes nothing and does not fail");
		/* AND A DIRECTORY THAT IS NOT THERE ANSWERS ZERO RATHER THAN RAISING. */
		check([controller cg_emptyTrashAtPath:[root stringByAppendingPathComponent:@"no-such-trash"]] == 0,
		      "and a trash that is not there is the same answer");
	}

	[controller release];
	[[NSFileManager defaultManager] removeItemAtPath:root error:NULL];

	printf("dock_trash: %s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
