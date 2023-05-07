{
  inputs,
  self,
  ...
}: {
  perSystem = {pkgs, ...}: let
    inherit (pkgs) callPackage dockerTools;
    inherit (dockerTools) buildLayeredImage;

    version = builtins.substring 0 8 self.lastModifiedDate;

    # make our own aipython3 since we have a lot of project-specific patches
    aipythonOverlay = import "${inputs.nixified-ai}/modules/aipython3/overlays.nix" pkgs;
    myOverlay = import ../overlay.nix pkgs;

    # thanks https://github.com/nixified-ai/flake/blob/master/modules/aipython3/default.nix!
    mkPythonPackages = overlayList: let
      python3' = pkgs.python3.override {
        packageOverrides = pkgs.lib.composeManyExtensions overlayList;
      };
    in
      python3'.pkgs;

    aipython3-nvidia = mkPythonPackages [
      aipythonOverlay.fixPackages
      aipythonOverlay.extraDeps
      aipythonOverlay.torchCuda
      myOverlay.osmosisFixes
      myOverlay.osmosisPackages
    ];

    aipython3-amd = mkPythonPackages [
      aipythonOverlay.fixPackages
      aipythonOverlay.extraDeps
      aipythonOverlay.torchRocm
      myOverlay.osmosisFixes
      myOverlay.osmosisPackages
    ];

    mkOsmosis = args: callPackage ./osmosis.nix ({inherit version;} // args);
    mkOsmosisDocker = osmosis:
      buildLayeredImage {
        name = "${osmosis.pname}-docker";
        tag = version;
        contents = [
          dockerTools.caCertificates
        ];
        config.Cmd = ["${osmosis}/bin/osmosis"];
      };
  in {
    packages = rec {
      coremltools = callPackage ./coremltools.nix {};

      osmosis-frontend = callPackage ./osmosis-frontend.nix {};

      osmosis-nvidia = mkOsmosis {
        aipython3 = aipython3-nvidia;
        isNvidia = true;
        inherit osmosis-frontend coremltools;
      };

      osmosis-nvidia-docker = mkOsmosisDocker osmosis-nvidia;

      osmosis-amd = mkOsmosis {
        aipython3 = aipython3-amd;
        inherit osmosis-frontend coremltools;
      };

      osmosis-amd-docker = mkOsmosisDocker osmosis-amd;
    };
  };
}
