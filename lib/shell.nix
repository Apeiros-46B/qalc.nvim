{ pkgs
, mkShell
, pkg-config
, cmake
, lldb
, libuv
, luajit
, libqalculate
}:

let
  llvm = pkgs.llvmPackages_18;
in (mkShell.override { stdenv = llvm.stdenv; }) {
	nativeBuildInputs = [
		pkg-config
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
		export CPLUS_INCLUDE_PATH="$CPATH"
		export PS1="(nix) $PS1"
	'';
}
