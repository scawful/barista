cmake_minimum_required(VERSION 3.20)
project(Barista
  VERSION 2.0.0
  DESCRIPTION "Brewing the perfect macOS status bar experience"
  LANGUAGES C CXX OBJC OBJCXX
)

# Set C/C++ standards
set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Build options
option(BUILD_TESTS "Build test programs" OFF)
option(BUILD_DOCS "Build documentation" OFF)

# Output directories
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

# macOS-specific settings
if(APPLE)
  set(CMAKE_OBJC_STANDARD 11)
  set(CMAKE_OBJCXX_STANDARD 17)
  set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0" CACHE STRING "Minimum macOS version")
endif()

# Compiler flags
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wextra")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra")

# Release build optimizations
set(CMAKE_C_FLAGS_RELEASE "-O3 -DNDEBUG")
set(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG")

# Include directories
include_directories(
  ${CMAKE_SOURCE_DIR}/helpers
  ${CMAKE_SOURCE_DIR}/helpers/event_providers
)

# Add subdirectories
add_subdirectory(helpers)
add_subdirectory(gui)

# Installation
set(INSTALL_BIN_DIR "${CMAKE_INSTALL_PREFIX}/bin")
set(INSTALL_CONFIG_DIR "${CMAKE_INSTALL_PREFIX}")

install(DIRECTORY ${CMAKE_SOURCE_DIR}/
  DESTINATION ${INSTALL_CONFIG_DIR}
  FILES_MATCHING
    PATTERN "*.lua"
    PATTERN "*.sh"
    PATTERN "*.json"
    PATTERN "*.md"
    PATTERN "*.txt"
    PATTERN "*.plist"
  PATTERN "build" EXCLUDE
  PATTERN ".git" EXCLUDE
  PATTERN "*.c" EXCLUDE
  PATTERN "*.cpp" EXCLUDE
  PATTERN "*.h" EXCLUDE
  PATTERN "*.m" EXCLUDE
  PATTERN "CMakeLists.txt" EXCLUDE
  PATTERN "Makefile" EXCLUDE
  PATTERN "makefile" EXCLUDE
)

# Print configuration summary
message(STATUS "")
message(STATUS "=== Barista Build Configuration ===")
message(STATUS "Version: ${PROJECT_VERSION}")
message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "C Compiler: ${CMAKE_C_COMPILER_ID} ${CMAKE_C_COMPILER_VERSION}")
message(STATUS "CXX Compiler: ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")
if(APPLE)
  message(STATUS "macOS Deployment Target: ${CMAKE_OSX_DEPLOYMENT_TARGET}")
endif()
message(STATUS "Install prefix: ${CMAKE_INSTALL_PREFIX}")
message(STATUS "===================================")
message(STATUS "")

