#===----------------------------------------------------------------------===#
#
# Agora's build for the Dock.
#
# **THE DOCK IS AN APPLICATION AND NOT A FRAMEWORK.** It consumes the AppKit as a built package and installs no
# package of its own; its one output is `Dock.app`. It is a SEPARATE CLIENT of the window server — the same shape
# Workspace has — because a Dock inside the file manager would be the mistake `window-server/DESIGN.md` names: one
# process owning the desktop and the tiles would make the tiles die with the desktop.
#
#===----------------------------------------------------------------------===#

cmake_minimum_required(VERSION 3.24)

project(AgoraDock VERSION 0.1.0 LANGUAGES C OBJC)

include(GNUInstallDirs)

set(CMAKE_POSITION_INDEPENDENT_CODE YES)
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

find_package(AgoraApp CONFIG REQUIRED)

add_executable(Dock
    src/main.m
    src/DockController.m
    src/DockLayout.m
    src/DockView.m)

target_include_directories(Dock PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
target_link_libraries(Dock PRIVATE AgoraApp::App)

# ---------------------------------------------------------------------------
# The bundle: Dock.app/Contents/{Info.plist, <platform>/<arch>/Dock}
# ---------------------------------------------------------------------------
# **THE DIRECTORY NAMES ARE libagora-core'S VOCABULARY, NOT CMAKE'S** — the same rule Workspace's build states and
# the same reason: the resolver spells the platform `Linux`, `FreeBSD`, `NetBSD`, `OpenBSD`, `DragonFly` or `MacOS`
# and the architecture `amd64`, `arm64`, `riscv64`, `i386` or `ppc64`, and a bundle laid out in CMake's spelling is
# one this tree cannot launch.
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    set(_bundle_platform "MacOS")
elseif(CMAKE_SYSTEM_NAME MATCHES "^(Linux|FreeBSD|NetBSD|OpenBSD|DragonFly)$")
    set(_bundle_platform "${CMAKE_SYSTEM_NAME}")
else()
    message(FATAL_ERROR
        "Dock: no bundle platform directory is named for ${CMAKE_SYSTEM_NAME}. Add the name to "
        "_CFBundleCopyPrimaryPlatformDirectoryName() in libagora-core first, so the resolver and the build "
        "cannot disagree.")
endif()

if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64|AMD64)$")
    set(_bundle_arch "amd64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
    set(_bundle_arch "arm64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^riscv64$")
    set(_bundle_arch "riscv64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(i[3-6]86|x86)$")
    set(_bundle_arch "i386")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(ppc64|ppc64le|powerpc64)$")
    set(_bundle_arch "ppc64")
else()
    message(FATAL_ERROR
        "Dock: no bundle architecture directory is named for ${CMAKE_SYSTEM_PROCESSOR}. Add the name to "
        "_CFBundleCopyArchitectureDirectoryNames() in libagora-core first.")
endif()

set(_bundle "${CMAKE_BINARY_DIR}/Dock.app")
set(DOCK_BUNDLE_EXECUTABLE "${_bundle}/Contents/${_bundle_platform}/${_bundle_arch}/Dock")

configure_file("${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in" "${_bundle}/Contents/Info.plist" @ONLY)
add_custom_command(TARGET Dock POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E remove -f "${_bundle}/Contents/MacOS/Dock"
    COMMAND "${CMAKE_COMMAND}" -E make_directory
            "${_bundle}/Contents/${_bundle_platform}/${_bundle_arch}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different "$<TARGET_FILE:Dock>"
            "${DOCK_BUNDLE_EXECUTABLE}"
    VERBATIM)

# **THE TESTS ARE A DEVELOPMENT ARTEFACT, AND A RELEASE DOES NOT BUILD THEM.** `include(CTest)` is what defines
# `BUILD_TESTING` — ON when a configure says nothing, which is what a developer's build wants — and turns testing on with
# it; the subdirectory is added only when it is on, so `-DBUILD_TESTING=OFF`, which is what the release driver passes,
# configures and compiles no test executable at all.
include(CTest)
if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
