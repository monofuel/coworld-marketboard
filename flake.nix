{
  description = "Coworld Marketboard";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forEachSystem = f: nixpkgs.lib.genAttrs systems (system:
        f (import nixpkgs { inherit system; })
      );
    in
    {
      devShells = forEachSystem (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.nim
            pkgs.pkg-config
          ];

          buildInputs = with pkgs; [
            # Windowing + input (required by windy)
            xorg.libX11
            xorg.libXcursor
            xorg.libXrandr
            xorg.libXi
            libGL

            # Device hotplug + gamepads (the ones that were missing)
            udev
            libevdev

            # Audio + font rendering (pulled by windy/pixie stack)
            alsa-lib
            fontconfig
            freetype
          ];

          shellHook = ''
            export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath [
              pkgs.xorg.libX11
              pkgs.xorg.libXcursor
              pkgs.libGL
              pkgs.udev
              pkgs.libevdev
              pkgs.alsa-lib
            ]}:$LD_LIBRARY_PATH
          '';
        };
      });
    };
}
