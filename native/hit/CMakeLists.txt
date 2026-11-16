cmake_minimum_required(VERSION 3.21)

project(quantumdogs_hit_manager LANGUAGES CXX)

include(FetchContent)

set(GODOTCPP_API_VERSION "4.7" CACHE STRING "Godot GDExtension API version")
set(GODOTCPP_TARGET "template_debug" CACHE STRING "Godot target configuration")
set(GODOT_CPP_SOURCE_DIR "" CACHE PATH "Existing godot-cpp source checkout")
option(HIT_MANAGER_OPTIMIZE "Optimize contact processing while retaining build-type debug symbols" ON)

if(GODOT_CPP_SOURCE_DIR AND EXISTS "${GODOT_CPP_SOURCE_DIR}/CMakeLists.txt")
	add_subdirectory("${GODOT_CPP_SOURCE_DIR}" "${CMAKE_BINARY_DIR}/godot-cpp")
else()
	FetchContent_Declare(
		godot-cpp
		GIT_REPOSITORY https://github.com/godotengine/godot-cpp.git
		GIT_TAG ed79ed472127e86f619d0ecc1274a943278d5257
	)
	FetchContent_MakeAvailable(godot-cpp)
endif()

add_library(hit_manager SHARED
	hit_manager.cpp
	register_types.cpp
)
target_link_libraries(hit_manager PRIVATE godot::cpp)
target_compile_features(hit_manager PRIVATE cxx_std_17)
if(HIT_MANAGER_OPTIMIZE AND CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
	# This hot contact path must not inherit -O0 simply because the Godot/editor
	# ABI uses template_debug. Keep -g and assertions; do not enable fast-math.
	target_compile_options(hit_manager PRIVATE -O2)
endif()

get_target_property(GODOTCPP_SUFFIX godot-cpp GODOTCPP_SUFFIX)
set(EXTENSION_OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../bin")
set_target_properties(
	godot-cpp
	PROPERTIES
		ARCHIVE_OUTPUT_DIRECTORY "$<1:${EXTENSION_OUTPUT_DIR}>"
)
set_target_properties(
	hit_manager
	PROPERTIES
		OUTPUT_NAME "hit_manager_combat${GODOTCPP_SUFFIX}"
		LIBRARY_OUTPUT_DIRECTORY "$<1:${EXTENSION_OUTPUT_DIR}>"
		RUNTIME_OUTPUT_DIRECTORY "$<1:${EXTENSION_OUTPUT_DIR}>"
		ARCHIVE_OUTPUT_DIRECTORY "$<1:${EXTENSION_OUTPUT_DIR}>"
)
if(WIN32)
	set_target_properties(hit_manager PROPERTIES PREFIX "")
endif()
