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

One tile per application in `-[NSWorkspace runningApplications]`, with the Dock itself filtered out by its own bundle
identifier (`io.github.agoradesktop.dock`). The icon comes from the application's bundle through Icon Services; an
application with no bundle on disk gets a muted placeholder rather than nothing. **The dot marks the application with
the keyboard** — every tile is running by definition, so a Mac-style "running" dot would carry no information, and the
one thing that changes is which application is in front.

Click a tile: `-[NSRunningApplication activateWithOptions:]` — raise **and** keyboard. Right-click: a menu with
**Quit**, which is `-terminate`, a request that every window close, not a kill.

## What is not here yet, named

- **A click on a tile also gives the DOCK the keyboard.** The window server's click-to-focus has no door for a window
  that never activates, so the Dock becomes the active application for a moment and the menu bar goes with it. The fix
  is a server request (`agora_window.set_activatable` or its equivalent) and an AppKit door over it; `main.m` already
  sets `NSApplicationActivationPolicyAccessory`, which the server does not yet read.
- **The trash does nothing on click, and takes no drops.** Its icon is here, but what a click or a drop MEANS is
  Workspace's (`WSTrash`) and the contract between the two is `WORKSPACE-PLAN.md` §5.3, still undecided. Cross-process
  drag does not exist in the window server yet, so a drop could not arrive.
- **No badges, no bounce, no magnification, no pinned applications.** Badges need `NSDockTile`; bounce needs
  `-requestUserAttention:` to reach the Dock; pinned applications need a persisted list and a Launch Services scan of
  the Applications directory; magnification is a drawing decision nobody has made.
- **No overflow.** A strip holds twelve tiles at 720 points (`DockLayout`, tested); more applications than that are
  simply not shown.

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
exactly the menu bar's bottom, tiles walk down from the top, the trash is pinned, twelve fit at 720 points, and a strip
with no room answers zero rather than a negative count.

## Licence

MIT — see [`LICENSE`](../LICENSE).
