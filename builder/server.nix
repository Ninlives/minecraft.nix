{ pkgs, lib }:
with lib;
let
  inherit (pkgs) fetchurl;

  buildFabricLibraries = libraries: map (lib: fetchJar lib) libraries;

  buildVanillaModules = versionInfo: assetsIndex:
    let server = fetchurl { inherit (versionInfo.downloads.server) url sha1; };
    in [{
      version = versionInfo.id;
      java = mkDefault (defaultJavaVersion versionInfo);
      mainJar = server;
      libraries.java = [ server ];
    }];

  buildFabricModules = versionInfo: assetsIndex: fabricProfile:
    let
      loaderVersion = fabricProfile.loader;
      loader = fabricLoaders.${loaderVersion};
      extraJavaLibraries = buildFabricLibraries
        (fabricProfile.libraries.server ++ loader.libraries);
    in (buildVanillaModules versionInfo assetsIndex) ++ [({
      libraries.java = extraJavaLibraries;
      mainClass = loader.mainClass.server;
    })];

in {
  build = mkBuild {
    baseModulePath = ../module/server.nix;
    inherit buildFabricModules buildVanillaModules;
  };
}
