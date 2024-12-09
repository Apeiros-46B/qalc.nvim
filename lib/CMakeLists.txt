cmake_minimum_required(VERSION 3.10)

project(qalcbridge
	VERSION 0.1.0
	DESCRIPTION "Lua bridge for libqalculate"
)

find_package(PkgConfig REQUIRED)
pkg_check_modules(LUA REQUIRED luajit)
pkg_check_modules(QALC REQUIRED libqalculate>=5.0.0)

add_library(${PROJECT_NAME} SHARED
	src/lib.cpp
	src/calculator.cpp
)
target_include_directories(${PROJECT_NAME}
	PRIVATE ${LUA_INCLUDE_DIRS}
	PRIVATE ${QALC_INCLUDE_DIRS}
	PRIVATE ${PROJECT_SOURCE_DIR}/include
)
target_link_libraries(${PROJECT_NAME} 
	${LUA_LIBRARIES}
	${QALC_LIBRARIES}
)
set_property(TARGET ${PROJECT_NAME} PROPERTY CXX_STANDARD 11)
