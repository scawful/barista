# Helpers CMakeLists.txt
# Builds all C/C++ helper binaries for SketchyBar

# Common frameworks and libraries for macOS
if(APPLE)
  find_library(COREFOUNDATION_LIB CoreFoundation)
  find_library(IOKIT_LIB IOKit)
  find_library(CARBON_LIB Carbon)
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
    if(NAME STREQUAL "state_manager" OR NAME STREQUAL "widget_manager")
      target_link_libraries(${NAME} PRIVATE pthread)
    endif()
  endif()
  
  # Set output to bin directory
  set_target_properties(${NAME} PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
  )
endforeach()

# Build C++ helper
foreach(SOURCE ${HELPER_CXX_SOURCES})
  get_filename_component(NAME ${SOURCE} NAME_WE)
  add_executable(${NAME} ${SOURCE})
  
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
  space_manager
  submenu_hover
  popup_anchor
  popup_hover
  popup_manager
  popup_guard
  icon_manager
  state_manager
  widget_manager
  menu_renderer
  menu_action
  RUNTIME DESTINATION bin
)

