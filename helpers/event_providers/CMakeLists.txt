# Event Providers CMakeLists.txt
# Builds event provider binaries

# Common header
set(EVENT_PROVIDER_HEADERS
  sketchybar.h
)

# CPU Load provider
add_executable(cpu_load
  cpu_load/cpu_load.c
  cpu_load/cpu.h
  sketchybar.h
)

target_include_directories(cpu_load PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}
  ${CMAKE_CURRENT_SOURCE_DIR}/cpu_load
)

set_target_properties(cpu_load PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
)

# Network Load provider
add_executable(network_load
  network_load/network_load.c
  network_load/network.h
  sketchybar.h
)

target_include_directories(network_load PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}
  ${CMAKE_CURRENT_SOURCE_DIR}/network_load
)

set_target_properties(network_load PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
)

# Installation
install(TARGETS
  cpu_load
  network_load
  RUNTIME DESTINATION bin
)

