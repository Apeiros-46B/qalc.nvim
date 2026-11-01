include(FindPackageHandleStandardArgs)

set(_LibUV_ROOT_HINTS
	${LibUV_ROOT}
	$ENV{LibUV_ROOT}
	${LIBUV_ROOT}
	$ENV{LIBUV_ROOT}
)

find_path(LibUV_INCLUDE_DIR
	NAMES uv.h
	HINTS ${_LibUV_ROOT_HINTS}
	PATH_SUFFIXES include
)
find_library(LibUV_LIBRARY
	NAMES uv libuv
	HINTS ${_LibUV_ROOT_HINTS}
	PATH_SUFFIXES lib lib64
)

if(LibUV_INCLUDE_DIR AND EXISTS "${LibUV_INCLUDE_DIR}/uv/version.h")
	file(STRINGS "${LibUV_INCLUDE_DIR}/uv/version.h" _LibUV_VERSION_LINES
		REGEX "^#define UV_VERSION_(MAJOR|MINOR|PATCH) [0-9]+$"
	)
	foreach(_component MAJOR MINOR PATCH)
		string(REGEX MATCH
			"UV_VERSION_${_component} ([0-9]+)"
			_LibUV_VERSION_MATCH
			"${_LibUV_VERSION_LINES}"
		)
		set(_LibUV_VERSION_${_component} "${CMAKE_MATCH_1}")
	endforeach()
	set(LibUV_VERSION
		"${_LibUV_VERSION_MAJOR}.${_LibUV_VERSION_MINOR}.${_LibUV_VERSION_PATCH}"
	)
endif()

find_package_handle_standard_args(LibUV
	REQUIRED_VARS LibUV_LIBRARY LibUV_INCLUDE_DIR
	VERSION_VAR LibUV_VERSION
)

if(LibUV_FOUND)
	set(LibUV_INCLUDE_DIRS "${LibUV_INCLUDE_DIR}")
	set(LibUV_LIBRARIES "${LibUV_LIBRARY}")

	if(NOT TARGET LibUV::LibUV)
		add_library(LibUV::LibUV UNKNOWN IMPORTED)
		set_target_properties(LibUV::LibUV PROPERTIES
			IMPORTED_LOCATION "${LibUV_LIBRARY}"
			INTERFACE_INCLUDE_DIRECTORIES "${LibUV_INCLUDE_DIR}"
		)
	endif()
endif()

mark_as_advanced(LibUV_INCLUDE_DIR LibUV_LIBRARY)
