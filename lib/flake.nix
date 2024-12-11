{
	inputs = {
		nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
	};
	outputs =
		{ nixpkgs, ... }:
		let
			# TODO: support more systems
			supportedSystems = [ "x86_64-linux" ];
			forAllSystems =
				file:
				(nixpkgs.lib.genAttrs supportedSystems (system: 
				let
					pkgs = (import nixpkgs { inherit system; });
				in
				{
					default = pkgs.callPackage file { inherit pkgs; };
				}));
		in
		{
			packages = forAllSystems ./default.nix;
			devShells = forAllSystems ./shell.nix;
		};
}
