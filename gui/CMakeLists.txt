# GUI CMakeLists.txt
# Builds Objective-C GUI applications

if(APPLE)
  find_library(COCOA_LIB Cocoa)
  find_library(FOUNDATION_LIB Foundation)
  
  # Compiler flags for Objective-C
  set(OBJC_FLAGS "-fobjc-arc")
  
  # Config Menu (v2 - main version)
  add_executable(config_menu_v2
    config_menu_v2.m
  )
  
  target_compile_options(config_menu_v2 PRIVATE ${OBJC_FLAGS})
  target_link_libraries(config_menu_v2 PRIVATE
    ${COCOA_LIB}
    ${FOUNDATION_LIB}
  )
  
  set_target_properties(config_menu_v2 PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
  )
  
  # Config Menu Enhanced
  add_executable(config_menu_enhanced
    config_menu_enhanced.m
  )
  
  target_compile_options(config_menu_enhanced PRIVATE ${OBJC_FLAGS})
  target_link_libraries(config_menu_enhanced PRIVATE
    ${COCOA_LIB}
    ${FOUNDATION_LIB}
  )
  
  set_target_properties(config_menu_enhanced PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
  )
  
  # Icon Browser
  add_executable(icon_browser
    icon_browser.m
  )
  
  target_compile_options(icon_browser PRIVATE ${OBJC_FLAGS})
  target_link_libraries(icon_browser PRIVATE
    ${COCOA_LIB}
    ${FOUNDATION_LIB}
  )
  
  set_target_properties(icon_browser PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
  )
  
  # Help Center
  add_executable(help_center
    help_center.m
  )
  
  target_compile_options(help_center PRIVATE ${OBJC_FLAGS})
  target_link_libraries(help_center PRIVATE
    ${COCOA_LIB}
    ${FOUNDATION_LIB}
  )
  
  set_target_properties(help_center PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
  )
  
  # Legacy config_menu (optional)
  if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/config_menu.m)
    add_executable(config_menu
      config_menu.m
    )
    
    target_compile_options(config_menu PRIVATE ${OBJC_FLAGS})
    target_link_libraries(config_menu PRIVATE
      ${COCOA_LIB}
      ${FOUNDATION_LIB}
    )
    
    set_target_properties(config_menu PROPERTIES
      RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
    )
  endif()
  
  # Installation
  install(TARGETS
    config_menu_v2
    config_menu_enhanced
    icon_browser
    help_center
    RUNTIME DESTINATION bin
  )
  
  if(TARGET config_menu)
    install(TARGETS config_menu RUNTIME DESTINATION bin)
  endif()
endif()

