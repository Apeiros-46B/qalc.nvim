{ pkgs
, mkShell
, cmake
, lldb
, libuv
, luajit
, libqalculate
}:

let
	llvm = pkgs.llvmPackages_18;
	cmakePrefixes = pkgs.lib.concatStringsSep ":" [
		"${pkgs.lib.getDev libuv}"
		"${pkgs.lib.getLib libuv}"
		"${pkgs.lib.getDev luajit}"
		"${pkgs.lib.getLib luajit}"
		"${pkgs.lib.getDev libqalculate}"
		"${pkgs.lib.getLib libqalculate}"
	];
in (mkShell.override { stdenv = llvm.stdenv; }) {
	nativeBuildInputs = [
		cmake
		lldb
		llvm.clang-tools
	];
	buildInputs = [
		libuv
		luajit
		libqalculate
	];
	shellHook = ''
		export CPATH="${llvm.clang.cc}/lib/clang/${llvm.clang.version}/include:$CPATH"
		export CMAKE_PREFIX_PATH="${cmakePrefixes}:$CMAKE_PREFIX_PATH"
		export CPLUS_INCLUDE_PATH="$CPATH"
		export PS1="(nix) $PS1"
	'';
}
