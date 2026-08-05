include(FindPackageHandleStandardArgs)

set(_LibQalculate_ROOT_HINTS
	${LibQalculate_ROOT}
	$ENV{LibQalculate_ROOT}
	${LIBQALCULATE_ROOT}
	$ENV{LIBQALCULATE_ROOT}
)

find_path(LibQalculate_INCLUDE_DIR
	NAMES libqalculate/Calculator.h
	HINTS ${_LibQalculate_ROOT_HINTS}
	PATH_SUFFIXES include
)
find_library(LibQalculate_LIBRARY
	NAMES qalculate libqalculate
	HINTS ${_LibQalculate_ROOT_HINTS}
	PATH_SUFFIXES lib lib64
)

set(_LibQalculate_VERSION_HEADER
	"${LibQalculate_INCLUDE_DIR}/libqalculate/includes.h"
)
if(LibQalculate_INCLUDE_DIR AND EXISTS "${_LibQalculate_VERSION_HEADER}")
	foreach(_component MAJOR MINOR MICRO)
		file(STRINGS "${_LibQalculate_VERSION_HEADER}" _LibQalculate_VERSION_LINE
			REGEX "^#define QALCULATE_${_component}_VERSION \\([0-9]+\\)$"
		)
		string(REGEX MATCH
			"QALCULATE_${_component}_VERSION \\(([0-9]+)\\)"
			_LibQalculate_VERSION_MATCH
			"${_LibQalculate_VERSION_LINE}"
		)
		set(_LibQalculate_VERSION_${_component} "${CMAKE_MATCH_1}")
	endforeach()
	set(LibQalculate_VERSION
		"${_LibQalculate_VERSION_MAJOR}.${_LibQalculate_VERSION_MINOR}.${_LibQalculate_VERSION_MICRO}"
	)
endif()

find_package_handle_standard_args(LibQalculate
	REQUIRED_VARS LibQalculate_LIBRARY LibQalculate_INCLUDE_DIR
	VERSION_VAR LibQalculate_VERSION
)

if(LibQalculate_FOUND)
	set(LibQalculate_INCLUDE_DIRS "${LibQalculate_INCLUDE_DIR}")
	set(LibQalculate_LIBRARIES "${LibQalculate_LIBRARY}")

	if(NOT TARGET LibQalculate::LibQalculate)
		add_library(LibQalculate::LibQalculate UNKNOWN IMPORTED)
		set_target_properties(LibQalculate::LibQalculate PROPERTIES
			IMPORTED_LOCATION "${LibQalculate_LIBRARY}"
			INTERFACE_INCLUDE_DIRECTORIES "${LibQalculate_INCLUDE_DIR}"
		)
	endif()
endif()

mark_as_advanced(LibQalculate_INCLUDE_DIR LibQalculate_LIBRARY)
