# dock

**Agora's Dock** — the running applications as tiles, in a vertical strip on a side of the screen, as its own client
of the window server.

Agora is an installable desktop environment for Linux and the BSDs; see the project README in the parent directory
(`../README.md`). The Dock sits at `NSDockWindowLevel` (20), below the menu bar's level (24), and owns no part of the
bar: clicking a tile asks the window server to bring that application forward, and the application's own menu bar
follows the keyboard.

## Where it is, and why

**Vertical, on the right, from the menu bar down — never under it.** The strip is 64 points wide and as tall as the
screen minus the bar, flush with the right edge; the tiles stack from the top downwards and the trash is pinned at the
bottom, so it stays where it is while applications come and go.

**It is a band and not a shelf: flat, square-cornered, semitransparent and darker than what is behind it** — edge to
edge, no inset and no border, so the wallpaper shows through the whole width and the strip belongs to the screen's
edge. That shape is the mockup's, and it is the difference a person sees between Agora's Dock and the Mac's floating
one.

**Left is the alternative, and it is one setting.** The layout is a mirror and nothing else changes:

```sh
AGORA_DOCK_POSITION=left          # for one run (the session script passes it through)
Dock --position left              # the flag, which is the most specific of the three
# and the persisted choice is `DockOrientation` in the defaults store, which a preferences UI will write;
# there is no `defaults` command in this tree yet.
```

**It reserves its strip.** The Dock tells the window server that 64 points of the edge are furniture
(`-[NSWindow cg_setReservedEdge:amount:]`, the AppKit face over `agora_window.set_reserved`), so every application's
`-visibleFrame` shrinks by exactly that and no maximised window is placed under the tiles. The reservation dies with
the window, so a Dock that crashes leaves no phantom strip.

## What a tile is

**A TILE IS A PLACE ON THE STRIP, NOT A RUNNING PROCESS** — `DockTile`, which is why a tile can outlive the
application it names. The strip shows the PINNED tiles first, in the user's order, then the applications from
`-[NSWorkspace runningApplications]` that nobody pinned, in the order the workspace named them; the Dock itself is
filtered out by its own bundle identifier (`io.github.agoradesktop.dock`). The icon comes from the application's bundle
through Icon Services; an application with no bundle on disk gets a muted placeholder rather than nothing.

**THE DOT MEANS "RUNNING", AND IT IS LIT FOR AS LONG AS THE PROCESS IS.** It used to mark the application with the
keyboard, on the argument that every tile was running by definition — a pinned tile is the counter-example that
argument needed. Now the strip holds both kinds, so the dot is what tells them apart: a pinned application keeps its
place while it is quit, dark, and lights up when it comes back. The frontmost application is not marked at all, which
is the Mac's answer too.

**A PINNED TILE IS WRITTEN DOWN.** `DockOrder` does the list arithmetic (pins first, then the rest; a move; a pin; an
unpin) and the Dock keeps the result under `DockPinnedApplications` in **its own defaults domain** — one dictionary per
pin: identifier, title, and the application's file. That file is `DockTile`'s, so a pin from a previous run is a tile
with an icon and a name and no application behind it until one appears. Anything that pins is a pasteboard-free
gesture: `Keep in Dock` on the tile's menu, or a drag.

**A BADGE IS THE APPLICATION'S OWN LABEL, DRAWN ON THE TILE'S OUTER CORNER.** The Dock does not compute it: the
application sets `NSDockTile -badgeLabel`, the AppKit pushes it through `agora-shell` 8, and the Dock asks
`NSDockTile +badgeLabelsByApplicationIdentifier` once per refresh and draws what it gets — a chip on the icon's
top-right, clamped to the tile. An application that never sets one contributes nothing, which is the ordinary case.

**The trash's icon is the icon of `~/.Trash`**, which is the Mac's own answer: Icon Services maps that path to the
theme's `user-trash` place icon. Which means the DIRECTORY has to exist — `stat` on a missing path is not a directory,
and the lookup then answers a generic file (a piece of paper in the trash slot; MEASURED). The session creates it at
login the way the Mac does, and the Dock creates it if it is missing so that a Dock started alone is not wrong. What a
click or a drop on it MEANS is still Workspace's (below).

**CLICKING A TILE ALWAYS BRINGS THAT APPLICATION FORWARD, AND A PIN WITHOUT ONE IS LAUNCHED.** A running
application is `-[NSRunningApplication activateWithOptions:]` — every window it has is raised in its level, **back to
front, so its own window order is kept**, and the frontmost takes the keyboard. An application with nothing to raise —
Workspace showing only its desktop — is ASKED to reopen instead and opens a file window, which is the Mac's behaviour
for that click. A pinned tile whose application has quit is a LAUNCH of the file the pin remembered (Launch Services by
identifier when the file has moved); the new process maps its window and takes the keyboard the way every launch does.

**THE DESKTOP IS NOT ONE OF THE TILES A PERSON ARRANGES, AND THAT IS A POLICY RATHER THAN A TASTE.** Workspace's tile
is ALWAYS on the strip, ALWAYS first, and cannot be removed: `DockOrder` hoists it to index 0 in every list it answers,
refuses to remove it, and the controller re-adds it to the pinned list whenever that list is loaded or rebuilt (so a
defaults file that has lost it, or an older build that never wrote it, gets it back). A drag of it is refused rather
than undone — the strip has no place above the top. Its menu has no `Keep in Dock`/`Remove from Dock` (there is
nothing to decide) and no `Quit` (ending the desktop is not a repair), but a **`Restart`**, which asks the application
to terminate through `quit_window` — `agora-shell` 12 — and starts it again as soon as its own snapshot says it has
gone. That is why the door exists at all: `close_window` asks each WINDOW and leaves the rest to the application, and
Workspace's windows are furniture, so closing them changes nothing about the process.

**AND THE GESTURE IS DECIDED BY THE RELEASE.** A press within a few points of where it started is a click; past that it
is a DRAG, the tile follows the pointer to the slot it is over, and letting go **repositions it in the Dock's order and
pins it** — `DockOrder -pinnedAfterMove:` keeps the pins that were there plus the one that was dragged. Dropping it
between two pinned tiles puts it between them; a drag can never lose a pin, and a press that is interrupted (the hand
leaves the strip and the release lands on somebody else's window) is undone by the next press, which restores the order
that is written down.

Right-click: a menu with **`Keep in Dock` / `Remove from Dock`** — the 10.6 wording for exactly this pair — and
**Quit**, which is `NSRunningApplication -terminate`: the application is asked to terminate (a request, not a kill),
and a compositor older than `agora-shell` 12 is asked to close the application's windows instead. A pinned
application that is not running has no Quit to offer, and it has no application menu to ask either: there is no window
for the question to reach, so the Dock's own rows are the whole menu.

**AND A CLICK OUTSIDE A TILE'S MENU IS THE MENU'S CLICK, NOT THE WINDOW'S UNDER IT.** A menu is a pop-up: the click
that dismisses it must not be a click on whatever it landed over, or a person dismissing a tile's menu watches the menu
bar change application — the desktop takes the keyboard for a click meant to say "never mind". So while a tile's menu
is open the Dock puts up an invisible, NON-ACTIVATABLE window over the screen (`-showMenuCatcher`: transparent, at
`NSMainMenuWindowLevel - 1`, below the bar and below the menu itself). The press lands there, the menu's session sees a
press addressed to another window and dismisses, and the keyboard stays where it was — no application is activated by
saying no.

**AND THE MENU IS THE APPLICATION'S ABOVE THE DOCK'S, WHICH IS ONE PANEL WITH TWO OWNERS.** An application may offer
items for its own tile — `-applicationDockMenu:` on its delegate, which is Apple's door — and those items appear ABOVE
the separator and the Quit, exactly as the Mac's do. That takes a round trip, because the panel is the Dock's (an
application cannot draw at the Dock's screen edge) and the items are the application's (the Dock cannot know what an
item means), so:

- the Dock asks through `+[NSDockMenu menuForApplication:]`, which asks the window server, which forwards
  `agora_window.dock_menu_requested` to the application's frontmost window;
- the application answers `-applicationDockMenu:`, and `NSDockMenu` carries the items across as a description — title,
  enabled, state, submenus, and an id for each row a person can choose;
- a pick goes back by that id (`+dispatchActionForItem:toApplication:`) and the APPLICATION sends its own action.

**IT ASKS EVERY TIME, AND THAT IS THE POINT.** A tile's menu is a picture of what the application can do at this
moment, so it is built when the menu opens and not before. The ask is bounded at half a second and falls back to the
Dock's own rows, so an application that is hung — or one that implements nothing — costs a right-click some latency
and never a panel that fails to open. See `NSDockMenu.h` in `libagora-app` for both halves and the format.

## What is not here yet, named

- **The trash does nothing on click, and takes no drops.** Its icon is here, but what a click or a drop MEANS is
  Workspace's (`WSTrash`) and the contract between the two is `WORKSPACE-PLAN.md` §5.3, still undecided. Cross-process
  drag does not exist in the window server yet, so a drop could not arrive.
- **No bounce, no magnification, and nothing that puts an application on the Dock besides a gesture.** Bounce needs
  `-requestUserAttention:` to reach the Dock; magnification is a drawing decision nobody has made; and a pin can only be
  made from a tile that exists — a drag, or the menu row — because an "add an application" panel would need a Launch
  Services scan of the Applications directory that this tier has no door for yet. (A pinned application stays on the
  strip with or without a process, which is the part that needed the list.)
- **No overflow.** A strip holds eleven tiles at 720 points (`DockLayout`, tested); more applications than that are
  simply not shown.
- **The session's wallpaper client appears as a tile**, with a placeholder icon, because it is an application with a
  window like any other. When the wallpaper moves to the layer the plan gives it (`kCGDesktopWindowLevel`), that tile
  goes with it.

**AND THE ONE THING THAT WAS BROKEN IS FIXED, NOT WORKED AROUND.** A click used to make the DOCK the active
application — the menu bar followed it, and the desktop was left with no bar at all. The window server now has
`agora_window.set_activatable` (protocol version 3, shell 4), the Dock says NO for its window, and the Dock exposes it
as `-[NSWindow cg_setActivatable:]` beside the reservation door. The pointer still reaches the tiles; the keyboard and
the bar stay where they were. `window-server/tests/window_list.c` asserts both halves: a window made non-activatable
gives the keyboard back, and `activate_window` cannot give it to one.

## Build and run

```sh
cmake -S . -B build -DCMAKE_C_COMPILER=/usr/bin/clang-19 -DCMAKE_OBJC_COMPILER=/usr/bin/clang-19 \
  -DCMAKE_PREFIX_PATH=../build-prefix
cmake --build build
ctest --test-dir build --output-on-failure

# against a running server, with Workspace already up:
WAYLAND_DISPLAY=agora ./build/Dock.app/Contents/*/*/Dock
```

`--seconds N` is a test's door: a Dock is a thing that stays, and a suite needs it to be able to leave.
`AGORA_DOCK_DIAG=1` prints what the strip believes after every snapshot.

## Tests

`tests/dock_layout.m` — **14 checks**, no compositor, no pixels: the strip is on the right (or the left), its top is
exactly the menu bar's bottom, tiles walk down from the top, the trash is pinned, eleven fit at 720 points, and a strip
with no room answers zero rather than a negative count.

The tile's MENU is tested where its two halves live rather than here, because neither half is the Dock's: the
description format and the id numbering are `libagora-app`'s (`appkit-dock-menu`, no compositor needed), and the round
trip through the window server is `appkit-dock-menu-wire`, which runs against `window-server`. What this component
adds to a menu — the separator, the Quit, and giving each of the application's rows the Dock's target — is the code
those two tests name.

## Licence

MIT — see [`LICENSE`](../LICENSE).
