cmake_minimum_required(VERSION 3.10)

project(qalcbridge
	VERSION 0.1.0
	DESCRIPTION "Lua bridge for libqalculate"
)

set(CMAKE_MODULE_PATH "${PROJECT_SOURCE_DIR}/cmake" ${CMAKE_MODULE_PATH})

find_package(LibUV REQUIRED)
find_package(LuaJIT REQUIRED)
find_package(LibQalculate 5.0.0 REQUIRED)

add_library(${PROJECT_NAME} SHARED
	src/lib.cpp
	src/math.cpp
	src/util.cpp
	src/worker.cpp
)
target_include_directories(${PROJECT_NAME}
	PRIVATE ${PROJECT_SOURCE_DIR}/include
)
target_link_libraries(${PROJECT_NAME}
	PRIVATE LibUV::LibUV
	PRIVATE LuaJIT::LuaJIT
	PRIVATE LibQalculate::LibQalculate
)
set_property(TARGET ${PROJECT_NAME} PROPERTY CXX_STANDARD 11)
