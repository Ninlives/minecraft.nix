{ pkgs, lib, authClientID, OS }:
with lib;
let
  inherit (pkgs) fetchurl libpulseaudio libGL flite alsa-lib unzip runCommand;
  inherit (pkgs.xorg) libXcursor libXrandr libXxf86vm;

  preloadLibraries = [
    libpulseaudio
    libXcursor
    libXrandr
    libXxf86vm # Needed only for versions <1.13
    libGL
    flite
    alsa-lib
  ];

  buildVanillaLibraries = artifacts:
    map (lib: fetchurl { inherit (lib.downloads.artifact) url sha1; })
    (filter (x: !(x.downloads ? "classifiers")) artifacts);
  buildNativeLibraries = artifacts:
    map (artif:
      let
        zip = fetchurl {
          inherit (artif.downloads.classifiers.${artif.natives.${OS}}) url sha1;
        };
      in runCommand "native" { buildInputs = [ unzip ]; } ''
        mkdir -p $out/lib
        unzip ${zip} -d $out/lib
        rm -rf $out/lib/META-INF
      '') (filter (x: (x.downloads ? "classifiers")) artifacts);
  buildAssets = versionInfo: assetsIndex:
    runCommand "assets" { } ''
      ${concatStringsSep "\n" (builtins.attrValues
        (flip mapAttrs assetsIndex.objects (name: a:
          let
            asset = fetchurl {
              sha1 = a.hash;
              url = "https://resources.download.minecraft.net/" + hashTwo;
            };
            hashTwo = builtins.substring 0 2 a.hash + "/" + a.hash;
          in ''
            mkdir -p $out/objects/${builtins.substring 0 2 a.hash}
            ln -sf ${asset} $out/objects/${hashTwo}
          '')))}
      mkdir -p $out/indexes
      ln -s ${builtins.toFile "assets.json" (builtins.toJSON assetsIndex)} \
          $out/indexes/${versionInfo.assets}.json
    '';
  buildFabricLibraries = libraries: map (lib: fetchJar lib) libraries;

  buildBasicModule = versionInfo: assetsIndex:
    let
      client = fetchurl { inherit (versionInfo.downloads.client) url sha1; };
      isAllowed = artifact:
        let
          lemma1 = acc: rule:
            if rule.action == "allow" then
              if rule ? os then rule.os.name == OS else true
            else if rule ? os then
              rule.os.name != OS
            else
              false;
        in if artifact ? rules then
          foldl' lemma1 false artifact.rules
        else
          true;
      artifacts = lib.filter isAllowed versionInfo.libraries;
    in {
      inherit authClientID;
      version = versionInfo.id;
      java = mkDefault (defaultJavaVersion versionInfo);
      libraries.java = buildVanillaLibraries artifacts ++ [ client ];
      libraries.native = buildNativeLibraries artifacts;
      libraries.preload = preloadLibraries;
      assets.directory = buildAssets versionInfo assetsIndex;
      assets.index = versionInfo.assets;
    };

  buildVanillaModules = versionInfo: assetsIndex: [
    (buildBasicModule versionInfo assetsIndex)
    { inherit (versionInfo) mainClass; }
  ];

  buildFabricModules = versionInfo: assetsIndex: fabricProfile:
    let
      loaderVersion = fabricProfile.loader;
      loader = fabricLoaders.${loaderVersion};
      extraJavaLibraries = buildFabricLibraries
        (fabricProfile.libraries.client ++ loader.libraries);
    in [
      (buildBasicModule versionInfo assetsIndex)
      ({
        libraries.java = extraJavaLibraries;
        mainClass = loader.mainClass.client;
      })
    ];

in {
  build = mkBuild {
    baseModulePath = ../module/client.nix;
    inherit buildFabricModules buildVanillaModules;
  };
}
