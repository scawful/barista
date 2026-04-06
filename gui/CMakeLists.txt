# GUI CMakeLists.txt
# Builds Objective-C GUI applications

if(APPLE)
  find_library(COCOA_LIB Cocoa)
  find_library(FOUNDATION_LIB Foundation)
  
  # Compiler flags for Objective-C
  set(OBJC_FLAGS "-fobjc-arc")
  set(BARISTA_PANEL_APP_NAME "BaristaControlPanel")
  set(BARISTA_PANEL_BUNDLE_DIR "${CMAKE_BINARY_DIR}/bin/${BARISTA_PANEL_APP_NAME}.app")
  set(BARISTA_PANEL_BUNDLE_EXEC "${BARISTA_PANEL_BUNDLE_DIR}/Contents/MacOS/${BARISTA_PANEL_APP_NAME}")
  set(BARISTA_PANEL_INFO_PLIST "${CMAKE_CURRENT_BINARY_DIR}/${BARISTA_PANEL_APP_NAME}-Info.plist")
  configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/BaristaControlPanel-Info.plist.in
    ${BARISTA_PANEL_INFO_PLIST}
    @ONLY
  )
  
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
    src/core/BaristaStyle.m
    src/core/BaristaStyle.h
    src/core/BaristaPanelView.m
    src/core/BaristaPanelView.h
    src/core/BaristaPanelWindow.m
    src/core/BaristaPanelWindow.h
    src/core/BaristaTabRegistry.m
    src/core/BaristaTabRegistry.h
    src/core/BaristaPanelState.m
    src/core/BaristaPanelState.h
    src/core/BaristaCommandBus.m
    src/core/BaristaCommandBus.h
    src/core/BaristaTabBaseViewController.m
    src/core/BaristaTabBaseViewController.h
    src/core/AppDelegate.m
    src/core/AppDelegate.h
    src/core/MainWindowController.m
    src/core/MainWindowController.h
  )
  
  # Tab view controllers
  set(CONFIG_MENU_TABS
    src/tabs/HomeTabViewController.m
    src/tabs/HomeTabViewController.h
    src/tabs/AppearanceTabViewController.m
    src/tabs/AppearanceTabViewController.h
    src/tabs/WidgetsTabViewController.m
    src/tabs/WidgetsTabViewController.h
    src/tabs/SpacesTabViewController.m
    src/tabs/SpacesTabViewController.h
    src/tabs/IconsTabViewController.m
    src/tabs/IconsTabViewController.h
    src/tabs/MenuTabViewController.m
    src/tabs/MenuTabViewController.h
    src/tabs/IntegrationsTabViewController.m
    src/tabs/IntegrationsTabViewController.h
    src/tabs/ThemesTabViewController.m
    src/tabs/ThemesTabViewController.h
    src/tabs/ShortcutsTabViewController.m
    src/tabs/ShortcutsTabViewController.h
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

  add_custom_command(
    OUTPUT ${BARISTA_PANEL_BUNDLE_EXEC}
    COMMAND ${CMAKE_COMMAND} -E make_directory ${BARISTA_PANEL_BUNDLE_DIR}/Contents
    COMMAND ${CMAKE_COMMAND} -E make_directory ${BARISTA_PANEL_BUNDLE_DIR}/Contents/MacOS
    COMMAND ${CMAKE_COMMAND} -E copy_if_different $<TARGET_FILE:config_menu> ${BARISTA_PANEL_BUNDLE_EXEC}
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${BARISTA_PANEL_INFO_PLIST} ${BARISTA_PANEL_BUNDLE_DIR}/Contents/Info.plist
    DEPENDS config_menu ${BARISTA_PANEL_INFO_PLIST}
    BYPRODUCTS ${BARISTA_PANEL_BUNDLE_DIR}/Contents/Info.plist
    COMMENT "Creating Barista Control Panel app bundle"
    VERBATIM
  )

  add_custom_target(barista_control_panel_app
    DEPENDS ${BARISTA_PANEL_BUNDLE_EXEC}
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
    src/core/ConfigurationManager.m
    src/core/BaristaStyle.m
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
endif()
