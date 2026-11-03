{
  description = "Radio Atlas: live radio on a rotatable globe, as a standalone Wayland app";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        radio-atlas = pkgs.callPackage ./nix/package.nix { };
        default = radio-atlas;
      });

      overlays.default = final: _prev: {
        radio-atlas = final.callPackage ./nix/package.nix { };
      };
    };
}
