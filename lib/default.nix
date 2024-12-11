{ pkgs, stdenv }:

stdenv.mkDerivation {
	pname = "libqalcbridge";
	version = "0.1.0";
	src = pkgs.lib.cleanSource ./.;
	nativeBuildInputs = with pkgs; [
		pkg-config
		cmake
		clang
		luajit
		libqalculate
	];
	buildInputs = with pkgs; [
		luajit
		libqalculate
	];
	installPhase = "install -Dm755 *.so -t $out/lib/";
	# postFixup = ''
	# 	patchelf --add-rpath ${pkgs.vulkan-loader}/lib $out/bin/*
	# '';
}
