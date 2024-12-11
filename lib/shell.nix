{ lib, pkgs, mkShell }:

mkShell rec {
	nativeBuildInputs = with pkgs; [
		pkg-config
		cmake
		clang
		gdb
	];
	buildInputs = with pkgs; [
		luajit
		libqalculate
	];
	LD_LIBRARY_PATH = lib.makeLibraryPath buildInputs;
}
