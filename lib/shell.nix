{ pkgs
, lib
, mkShell
, clangStdenv
, pkg-config
, cmake
, lldb
, llvmPackages
, libuv
, luajit
, libqalculate
}:

(mkShell.override { stdenv = clangStdenv; }) rec {
	nativeBuildInputs = [
		pkg-config
		cmake
		lldb
		llvmPackages.clang-tools
	];
	buildInputs = [
		libuv
		luajit
		libqalculate
	];
	LD_LIBRARY_PATH = lib.makeLibraryPath buildInputs;
	shellHook = ''
		export CPATH="$(${llvmPackages.clang}/bin/clang -print-resource-dir)/include:$CPATH"
		export CPLUS_INCLUDE_PATH="$CPATH"
		PS1="(nix) $PS1"
	'';
}
