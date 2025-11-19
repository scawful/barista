# Menus CMakeLists.txt
# Builds menu-related binaries

if(APPLE)
  find_library(CARBON_LIB Carbon)
  find_library(SKYLIGHT_LIB SkyLight
    PATHS /System/Library/PrivateFrameworks
    NO_DEFAULT_PATH
  )
  
  add_executable(menus menus.c)
  
  target_link_libraries(menus PRIVATE
    ${CARBON_LIB}
    ${SKYLIGHT_LIB}
  )
  
  # Add framework search path
  target_compile_options(menus PRIVATE
    -F/System/Library/PrivateFrameworks/
  )
  
  set_target_properties(menus PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
  )
  
  # Installation
  install(TARGETS menus RUNTIME DESTINATION bin)
endif()

