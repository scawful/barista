cmake_minimum_required(VERSION 3.10)
project(barista_gui)

# GUI CMakeLists.txt
# Builds Objective-C GUI applications

if(APPLE)
  find_library(COCOA_LIB Cocoa)
  find_library(FOUNDATION_LIB Foundation)
  
  # Compiler flags for Objective-C
  set(OBJC_FLAGS "-fobjc-arc")
  
  # Include directories for organized structure
  include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/src/core
    ${CMAKE_CURRENT_SOURCE_DIR}/src/tabs
  )
  
  # Unified Config Menu (modular architecture)
  # Core components
  set(CONFIG_MENU_CORE
    src/main.m
    src/core/ConfigurationManager.m
    src/core/ConfigurationManager.h
    src/core/AppDelegate.m
    src/core/AppDelegate.h
    src/core/MainWindowController.m
    src/core/MainWindowController.h
  )
  
  # Tab view controllers
  set(CONFIG_MENU_TABS
    src/tabs/AppearanceTabViewController.m
    src/tabs/AppearanceTabViewController.h
    src/tabs/WidgetsTabViewController.m
    src/tabs/WidgetsTabViewController.h
    src/tabs/SpacesTabViewController.m
    src/tabs/SpacesTabViewController.h
    src/tabs/IconsTabViewController.m
    src/tabs/IconsTabViewController.h
    src/tabs/IntegrationsTabViewController.m
    src/tabs/IntegrationsTabViewController.h
    src/tabs/ThemesTabViewController.m
    src/tabs/ThemesTabViewController.h
    src/tabs/ShortcutsTabViewController.m
    src/tabs/ShortcutsTabViewController.h
    src/tabs/WorkflowTabViewController.m
    src/tabs/WorkflowTabViewController.h
    src/tabs/LaunchAgentsTabViewController.m
    src/tabs/LaunchAgentsTabViewController.h
    src/tabs/DebugTabViewController.m
    src/tabs/DebugTabViewController.h
    src/tabs/PerformanceTabViewController.m
    src/tabs/PerformanceTabViewController.h
    src/tabs/AdvancedTabViewController.m
    src/tabs/AdvancedTabViewController.h
  )
  
  add_executable(config_menu
    ${CONFIG_MENU_CORE}
    ${CONFIG_MENU_TABS}
  )
  
  target_compile_options(config_menu PRIVATE ${OBJC_FLAGS})
  target_link_libraries(config_menu PRIVATE
    ${COCOA_LIB}
    ${FOUNDATION_LIB}
  )
  
  set_target_properties(config_menu PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
  )
  
  # Legacy config_menu_v2 (deprecated, kept for compatibility)
  if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/config_menu_v2.m)
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
  endif()
  
  # Legacy config_menu_enhanced (deprecated, kept for reference)
  if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/config_menu_enhanced.m)
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
  endif()
  
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
  
  # Installation
  install(TARGETS
    config_menu
    icon_browser
    help_center
    RUNTIME DESTINATION bin
  )
  
  # Install legacy targets if they exist
  if(TARGET config_menu_v2)
    install(TARGETS config_menu_v2 RUNTIME DESTINATION bin)
  endif()
  
  if(TARGET config_menu_enhanced)
    install(TARGETS config_menu_enhanced RUNTIME DESTINATION bin)
  endif()
endif()
