# The Dock's tests.
#
# The layout is geography, and geography is the part that can be wrong without looking wrong: a strip that overlaps
# the menu bar or a trash that drifts are both plausible pictures. So it is asserted with no window, no compositor
# and no pixels — `dock_layout` compiles `DockLayout.m` as it ships.

add_executable(dock_layout dock_layout.m "${CMAKE_CURRENT_SOURCE_DIR}/../src/DockLayout.m")
target_include_directories(dock_layout PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../src")
target_link_libraries(dock_layout PRIVATE AgoraApp::App)
# **THE APPKIT'S OWN PRIVATE DEPENDENCIES ARE NOT PROPAGATED AS A RUNPATH** (a shared library's DT_RUNPATH is not
# inherited), so a test that loads the AppKit has to be told where Launch Services and Icon Services are — the same
# reason `libagora-app`'s tests carry an `LD_LIBRARY_PATH`. The directory comes from the imported target, so this
# follows the prefix rather than naming it.
set(_dock_test_env "LD_LIBRARY_PATH=$<TARGET_FILE_DIR:AgoraApp::App>")
add_test(NAME dock-layout COMMAND dock_layout)
set_tests_properties(dock-layout PROPERTIES ENVIRONMENT "${_dock_test_env}")

# **THE ORDER AND THE TILES, WITH NO WINDOW.** Which tiles the strip shows and in what order is the part a person
# notices and the part no screenshot can assert: a pin that vanishes when its application quits, a drag that does not
# stick, an unpin that takes the wrong row. `dock_order` compiles the two units it is about — the list arithmetic and
# the tile value — and drives them with identifiers.
add_executable(dock_order dock_order.m "${CMAKE_CURRENT_SOURCE_DIR}/../src/DockOrder.m"
	"${CMAKE_CURRENT_SOURCE_DIR}/../src/DockTile.m")
target_include_directories(dock_order PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../src")
target_link_libraries(dock_order PRIVATE AgoraApp::App)
add_test(NAME dock-order COMMAND dock_order)
set_tests_properties(dock-order PROPERTIES ENVIRONMENT "${_dock_test_env}")

# **A TILE'S BADGE AND ITS RUNNING DOT, MEASURED IN PIXELS.** The view is drawn offscreen and the ink counted: a tile
# with a label paints the badge's red in its top-right corner, the same tile with no label paints none, a running
# application's tile carries the white dot and a pinned tile whose application has quit carries none. This one compiles
# the whole DockView, because the question is what it DRAWS.
add_executable(dock_badge dock_badge.m "${CMAKE_CURRENT_SOURCE_DIR}/../src/DockView.m"
	"${CMAKE_CURRENT_SOURCE_DIR}/../src/DockLayout.m" "${CMAKE_CURRENT_SOURCE_DIR}/../src/DockTile.m")
target_include_directories(dock_badge PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../src")
target_link_libraries(dock_badge PRIVATE AgoraApp::App m)
# **A DRAG FROM ANOTHER APPLICATION: WHAT THE STRIP TAKES AND WHERE IT WOULD LAND.** An application bundle dropped on
# the Dock is pinned at the slot the pointer was over, so the two questions worth measuring are "is this a drag the Dock
# accepts" and "which slot does the strip report" — plus what a bundle on disk becomes. A real Dock needs a screen; the
# strip drawn offscreen and a recording stand-in for the controller need none.
add_executable(dock_pin dock_pin.m "${CMAKE_CURRENT_SOURCE_DIR}/../src/DockView.m"
	"${CMAKE_CURRENT_SOURCE_DIR}/../src/DockLayout.m" "${CMAKE_CURRENT_SOURCE_DIR}/../src/DockTile.m"
	"${CMAKE_CURRENT_SOURCE_DIR}/../src/DockOrder.m")
target_include_directories(dock_pin PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../src")
target_link_libraries(dock_pin PRIVATE AgoraApp::App m)
add_test(NAME dock-pin COMMAND dock_pin)
set_tests_properties(dock-pin PROPERTIES ENVIRONMENT "${_dock_test_env}")

add_test(NAME dock-badge COMMAND dock_badge)
set_tests_properties(dock-badge PROPERTIES ENVIRONMENT "${_dock_test_env}")
