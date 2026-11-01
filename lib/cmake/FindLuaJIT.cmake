include(FindPackageHandleStandardArgs)

set(_LuaJIT_ROOT_HINTS
	${LuaJIT_ROOT}
	$ENV{LuaJIT_ROOT}
	${LUAJIT_ROOT}
	$ENV{LUAJIT_ROOT}
)

find_path(LuaJIT_INCLUDE_DIR
	NAMES luajit.h
	HINTS ${_LuaJIT_ROOT_HINTS}
	PATH_SUFFIXES
		include/luajit-2.1
		include/luajit-2.0
		luajit-2.1
		luajit-2.0
		include
		src
)
find_library(LuaJIT_LIBRARY
	NAMES luajit-5.1 luajit lua51
	HINTS ${_LuaJIT_ROOT_HINTS}
	PATH_SUFFIXES lib lib64 src
)

if(LuaJIT_INCLUDE_DIR AND EXISTS "${LuaJIT_INCLUDE_DIR}/luajit.h")
	file(STRINGS "${LuaJIT_INCLUDE_DIR}/luajit.h" _LuaJIT_VERSION_LINE
		REGEX "^#define LUAJIT_VERSION[ \t]+\"LuaJIT [0-9]"
	)
	string(REGEX MATCH
		"[0-9]+\\.[0-9]+(\\.[0-9]+([-.][0-9A-Za-z.]+)?)?"
		LuaJIT_VERSION
		"${_LuaJIT_VERSION_LINE}"
	)
endif()

find_package_handle_standard_args(LuaJIT
	REQUIRED_VARS LuaJIT_LIBRARY LuaJIT_INCLUDE_DIR
	VERSION_VAR LuaJIT_VERSION
)

if(LuaJIT_FOUND)
	set(LuaJIT_INCLUDE_DIRS "${LuaJIT_INCLUDE_DIR}")
	set(LuaJIT_LIBRARIES "${LuaJIT_LIBRARY}")

	if(NOT TARGET LuaJIT::LuaJIT)
		add_library(LuaJIT::LuaJIT UNKNOWN IMPORTED)
		set_target_properties(LuaJIT::LuaJIT PROPERTIES
			IMPORTED_LOCATION "${LuaJIT_LIBRARY}"
			INTERFACE_INCLUDE_DIRECTORIES "${LuaJIT_INCLUDE_DIR}"
		)
	endif()
endif()

mark_as_advanced(LuaJIT_INCLUDE_DIR LuaJIT_LIBRARY)
