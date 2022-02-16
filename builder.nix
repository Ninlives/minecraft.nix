{ pkgs ? import <nixpkgs> { }, lib ? pkgs.lib, clientID, OS ? "linux" }:
with lib;
let
  inherit (pkgs)
    fetchurl libpulseaudio libGL flite alsa-lib unzip writeShellScript jq jre
    runCommand;
  inherit (pkgs.xorg) libXcursor libXrandr libXxf86vm;
  inherit (pkgs.writers) writePython3;
  inherit (import ./launcher.nix { inherit pkgs lib; }) launchWrapper;
  manifests = importJSON ./vanilla/manifests.json;
  fabricProfiles = importJSON ./fabric/profiles.json;
  fabricLibraries = importJSON ./fabric/libraries.json;
  fabricLoaders = importJSON ./fabric/loaders.json;

  preloadLibraries = [
    libpulseaudio
    libXcursor
    libXrandr
    libXxf86vm # Needed only for versions <1.13
    libGL
    flite
    alsa-lib
  ];

  convertVersion = v: "v" + replaceStrings [ "." " " ] [ "_" "_" ] v;
  fetchJar = name:
    let
      inherit (fabricLibraries.${name}) repo hash;
      splitted = splitString ":" name;
      org = builtins.elemAt splitted 0;
      art = builtins.elemAt splitted 1;
      ver = builtins.elemAt splitted 2;
      path =
        "${replaceStrings [ "." ] [ "/" ] org}/${art}/${ver}/${art}-${ver}.jar";
      url = "${repo}/${path}";
    in fetchurl {
      inherit url;
      ${hash.type} = hash.value;
    };

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
              url = "http://resources.download.minecraft.net/" + hashTwo;
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
      inherit clientID;
      version = versionInfo.id;
      libraries.java = buildVanillaLibraries artifacts ++ [ client ];
      libraries.native = buildNativeLibraries artifacts;
      libraries.preload = preloadLibraries;
      assets.directory = buildAssets versionInfo assetsIndex;
      assets.index = versionInfo.assets;
    };

  buildVanillaModules = versionInfo: assetsIndex: [
    (buildBasicModule versionInfo assetsIndex)
    {

      inherit (versionInfo) mainClass;
    }
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

  mkLauncher = modules:
    let
      final = evalModules {
        modules = modules
          ++ [ ({ _module.args.pkgs = pkgs; }) (import ./module) ];
      };
    in final.config.launcher // {
      withConfig = extraConfig: mkLauncher (modules ++ toList extraConfig);
    };

  buildMc = versionInfo: assetsIndex: fabricProfile:
    let
      fabric = {
        client =
          mkLauncher (buildFabricModules versionInfo assetsIndex fabricProfile);
      };
    in {
      vanilla.client = mkLauncher (buildVanillaModules versionInfo assetsIndex);
    } // (optionalAttrs (fabricProfile != null) { inherit fabric; });

  prepareMc = gameVersion: assets:
    let
      versionInfo = importJSON (fetchurl { inherit (assets) url sha1; });
      assetsIndex =
        importJSON (fetchurl { inherit (versionInfo.assetIndex) url sha1; });
      fabricProfile = fabricProfiles.${gameVersion} or null;
    in buildMc versionInfo assetsIndex fabricProfile;
in mapAttrs' (gameVersion: assets: {
  name = convertVersion gameVersion;
  value = prepareMc gameVersion assets;
}) manifests
