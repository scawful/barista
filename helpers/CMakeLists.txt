# Helpers CMakeLists.txt
# Builds all C/C++ helper binaries for SketchyBar

# Common frameworks and libraries for macOS
if(APPLE)
  find_library(COREFOUNDATION_LIB CoreFoundation)
  find_library(COREAUDIO_LIB CoreAudio)
  find_library(AUDIOTOOLBOX_LIB AudioToolbox)
  find_library(IOKIT_LIB IOKit)
  find_library(CARBON_LIB Carbon)
  find_library(SYSTEMCONFIGURATION_LIB SystemConfiguration)
  find_library(SKYLIGHT_LIB SkyLight
    PATHS /System/Library/PrivateFrameworks
    NO_DEFAULT_PATH
  )
endif()

# Helper binaries
set(HELPER_SOURCES
  clock_widget.c
  system_info_widget.c
  space_manager.c
  submenu_hover.c
  popup_anchor.c
  popup_hover.c
  popup_manager.c
  popup_guard.c
  icon_manager.c
  state_manager.c
  widget_manager.c
  menu_renderer.c
)

# C++ helper
set(HELPER_CXX_SOURCES
  menu_action.cpp
)

# Objective-C helpers
set(HELPER_OBJC_SOURCES
  runtime_context_helper.m
  space_visual_helper.m
  volume_popup_helper.m
)

# Build C helpers
foreach(SOURCE ${HELPER_SOURCES})
  get_filename_component(NAME ${SOURCE} NAME_WE)
  add_executable(${NAME} ${SOURCE})
  
  if(APPLE)
    target_link_libraries(${NAME} PRIVATE
      ${COREFOUNDATION_LIB}
      ${IOKIT_LIB}
    )
    
    # Special handling for specific binaries
    if(NAME STREQUAL "state_manager" OR NAME STREQUAL "widget_manager"
        OR NAME STREQUAL "system_info_widget")
      target_link_libraries(${NAME} PRIVATE pthread)
    endif()
    if(NAME STREQUAL "system_info_widget")
      target_link_libraries(${NAME} PRIVATE ${SYSTEMCONFIGURATION_LIB})
    endif()
  endif()
  
  # Set output to bin directory
  set_target_properties(${NAME} PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
  )
endforeach()

# Keep event-driven dismissal and click-time popup switching independently
# addressable while sharing the same implementation. The distinct click binary
# lets older installs fall back safely instead of invoking a stale manager ABI.
add_executable(popup_switch popup_manager.c)
if(APPLE)
  target_link_libraries(popup_switch PRIVATE
    ${COREFOUNDATION_LIB}
    ${IOKIT_LIB}
  )
endif()
set_target_properties(popup_switch PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
)

# Keep the scheduled widget and on-demand popup entrypoints independently
# addressable while sharing the same implementation.
add_executable(system_info_popup_helper system_info_widget.c)
if(APPLE)
  target_link_libraries(system_info_popup_helper PRIVATE
    ${COREFOUNDATION_LIB}
    ${IOKIT_LIB}
    ${SYSTEMCONFIGURATION_LIB}
    pthread
  )
endif()
set_target_properties(system_info_popup_helper PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
)

# Build C++ helper
foreach(SOURCE ${HELPER_CXX_SOURCES})
  get_filename_component(NAME ${SOURCE} NAME_WE)
  add_executable(${NAME} ${SOURCE})
  
  set_target_properties(${NAME} PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
  )
endforeach()

# Build Objective-C helpers
foreach(SOURCE ${HELPER_OBJC_SOURCES})
  get_filename_component(NAME ${SOURCE} NAME_WE)
  add_executable(${NAME} ${SOURCE})

  if(APPLE)
    find_library(COCOA_LIB Cocoa)
    find_library(FOUNDATION_LIB Foundation)
    target_compile_options(${NAME} PRIVATE -fobjc-arc)
    if(NAME STREQUAL "volume_popup_helper")
      target_link_libraries(${NAME} PRIVATE
        ${FOUNDATION_LIB}
        ${COREAUDIO_LIB}
        ${AUDIOTOOLBOX_LIB}
      )
    else()
      target_link_libraries(${NAME} PRIVATE
        ${COCOA_LIB}
        ${FOUNDATION_LIB}
      )
    endif()
  endif()

  set_target_properties(${NAME} PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
  )
endforeach()

# Event providers subdirectory
if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/event_providers/CMakeLists.txt)
  add_subdirectory(event_providers)
endif()

# Menus subdirectory
if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/menus/CMakeLists.txt)
  add_subdirectory(menus)
endif()

# Installation
install(TARGETS
  clock_widget
  system_info_widget
  system_info_popup_helper
  space_manager
  submenu_hover
  popup_anchor
  popup_hover
  popup_manager
  popup_switch
  popup_guard
  icon_manager
  state_manager
  widget_manager
  menu_renderer
  menu_action
  runtime_context_helper
  space_visual_helper
  volume_popup_helper
  RUNTIME DESTINATION bin
)
