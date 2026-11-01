{ pkgs, stdenv }:

let
	cmakePrefixes = pkgs.lib.concatStringsSep ";" [
		"${pkgs.lib.getDev pkgs.libuv}"
		"${pkgs.lib.getLib pkgs.libuv}"
		"${pkgs.lib.getDev pkgs.luajit}"
		"${pkgs.lib.getLib pkgs.luajit}"
		"${pkgs.lib.getDev pkgs.libqalculate}"
		"${pkgs.lib.getLib pkgs.libqalculate}"
	];
in stdenv.mkDerivation {
	pname = "libqalcbridge";
	version = "0.1.0";
	src = pkgs.lib.cleanSource ./.;
	nativeBuildInputs = with pkgs; [
		cmake
		clang
	];
	buildInputs = with pkgs; [
		luajit
		libqalculate
		libuv
	];
	cmakeFlags = [ "-DCMAKE_PREFIX_PATH=${cmakePrefixes}" ];
	installPhase = "install -Dm755 *.so -t $out/lib/";
}
