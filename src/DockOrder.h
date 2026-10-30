/*
 * DockOrder.h — which tiles the Dock shows and in what order, as arithmetic on identifiers.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * **THE ORDER IS THE WHOLE OF WHAT A DRAG CHANGES, SO IT IS A PURE FUNCTION OF TWO LISTS.** `DockLayout` answers
 * WHERE a tile is; this answers WHICH tiles there are. Both are arithmetic on plain values — the layout on
 * rectangles, this on bundle identifiers — which is what lets each be asserted with no window, no compositor and no
 * pixels (`tests/dock_order.m`).
 *
 * THE THREE QUESTIONS, AND THE ANSWERS THIS TIER HAS DECIDED ON (the Mac's, stated rather than discovered):
 *
 *   * **A PINNED APPLICATION IS ON THE DOCK WHETHER OR NOT IT IS RUNNING**, in the user's order, BEFORE the running
 *     applications that are not pinned. That is the whole point of pinning: the tile is a place on the strip, not a
 *     report that something is running.
 *   * **A RUNNING APPLICATION THAT IS NOT PINNED COMES AFTER THEM**, in the order the workspace named it (which is
 *     the window list's order, back to front). A Dock is a place for programs; the ones nobody placed stay at the
 *     end, which is also where a Mac puts them.
 *   * **A DRAG PINS.** Dropping a tile somewhere in the strip is a statement about the Dock's SHAPE, and a tile that
 *     flew back to the end the moment its application quit would not be one. So the dragged identifier joins the
 *     pinned list at the position it was dropped in, and the pinned list stays the pins plus that one — an unpinned
 *     running application that happened to be displayed among them is not pinned by somebody else's drag.
 */
#ifndef DOCK_ORDER_H
#define DOCK_ORDER_H

#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>

/* **THE DISPLAYED ORDER.** Both inputs are arrays of bundle identifiers; the pinned ones keep their order and come
 * first, the running ones fill in behind, and an identifier named twice appears once. Returns an autoreleased array
 * of the identifiers that appear in either input, in that order. */
NSArray *DockOrderIdentifiers(NSArray *pinnedIdentifiers, NSArray *runningIdentifiers);

/* **ONE ITEM MOVED, WHICH IS WHAT A DRAG STEP IS.** `from` and `to` are positions in the array BEFORE the move (which
 * is what a drop index is), and an out-of-range `to` is clamped to the end rather than refused. Generic over what the
 * array holds, because the controller moves its TILES and the pinned list moves IDENTIFIERS. Returns a new
 * autoreleased array; the input is untouched. */
NSArray *DockOrderMoving(NSArray *items, NSUInteger from, NSUInteger to);

/* **THE PINNED LIST AFTER A DRAG.** `displayed` is the order the strip is showing when the hand lets go — the
 * controller has already moved the tile there — and the answer is the identifiers that were ALREADY pinned plus
 * `dragged`, in that displayed order. Anything else that was running and unpinned is deliberately dropped: it keeps
 * its place at the end of the strip, and it is not the drag's business to pin it. */
NSArray *DockOrderPinnedAfterMove(NSArray *pinnedIdentifiers, NSArray *displayedIdentifiers, NSString *dragged);

/* **AND THE MENU'S TWO ROWS.** Pinning appends — a tile only reachable through the menu has no drop position to
 * respect — and an identifier already pinned is not pinned twice; unpinning removes it, which for a running
 * application leaves its tile at the end of the strip and for one that is not running takes the tile away. */
NSArray *DockOrderPinnedAdding(NSArray *pinnedIdentifiers, NSString *identifier);
NSArray *DockOrderPinnedRemoving(NSArray *pinnedIdentifiers, NSString *identifier);

#endif /* DOCK_ORDER_H */
