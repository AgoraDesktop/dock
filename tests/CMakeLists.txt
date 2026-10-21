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
