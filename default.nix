{ pkgs ? import <nixpkgs> { }, lib ? pkgs.lib, clientID, OS ? "linux" }:
with lib;
let
  inherit (pkgs)
    fetchurl libpulseaudio libGL flite alsa-lib unzip writeShellScriptBin jq jre
    runCommand;
  inherit (pkgs.xorg) libXcursor libXrandr libXxf86vm;
  inherit (pkgs.writers) writePython3;
  manifests = importJSON ./vanilla/manifests.json;
  fabricProfiles = importJSON ./fabric/profiles.json;
  fabricLibraries = importJSON ./fabric/libraries.json;
  fabricLoaders = importJSON ./fabric/loaders.json;

  libPath = makeLibraryPath [
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

  auth = writePython3 "checkAuth" {
    libraries = with pkgs.python3Packages; [ requests pyjwt colorama ];
    flakeIgnore = [ "E501" "E402" "W391" ];
  } ''
    ${builtins.replaceStrings [ "@CLIENT_ID@" ] [ clientID ]
    (builtins.readFile ./auth/msa.py)}
    ${builtins.readFile ./auth/login.py}
  '';

  launchScript = { mainClass, versionInfo, javaLibraries, nativeLibraries
    , assets, mods ? [ ] }:
    let json = "${jq}/bin/jq --raw-output";
    in writeShellScriptBin "minecraft" ''
      RED='\033[0;31m'
      FIN='\033[0m'
      PROFILE="$HOME/.local/share/minecraft.nix/profile.json"
      for((i=1;i<=$#;i++)); do
        if [[ "''${!i}" == "--mcnix-profile" && $i -lt $# ]];then
          p=$((i+1))
          PROFILE=''${!p}
          break
        fi
      done
      ${auth} --profile "$PROFILE" || (echo -e "''${RED}Refused to launch game.''${FIN}"; exit 1)
      UUID=$(${json} '.["id"]' "$PROFILE")
      USER_NAME=$(${json} '.["name"]' "$PROFILE")
      ACCESS_TOKEN=$(${json} '.["mc_token"]["__value"]' "$PROFILE")

      export LD_LIBRARY_PATH=${libPath}''${LD_LIBRARY_PATH:+':'}$LD_LIBRARY_PATH
      exec ${jre}/bin/java \
        -Djava.library.path='${
          concatMapStringsSep ":" (native: "${native}/lib") nativeLibraries
        }' \
        -cp '${concatStringsSep ":" javaLibraries}' \
        ${
          optionalString (mods != [ ])
          "-Dfabric.addMods='${concatStringsSep ":" mods}'"
        } \
        ${mainClass} \
        --version "${versionInfo.id}" \
        --assetsDir "${assets}" \
        --assetIndex "${versionInfo.assets}" \
        --uuid "$UUID" \
        --accessToken "$ACCESS_TOKEN" \
        "$@"
    '';

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
  buildArguments = versionInfo: assetsIndex:
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
      javaLibraries = buildVanillaLibraries artifacts ++ [ client ];
      nativeLibraries = buildNativeLibraries artifacts;
      assets = buildAssets versionInfo assetsIndex;
    };

  buildVanillaClient = versionInfo: assetsIndex:
    launchScript (buildArguments versionInfo assetsIndex // {
      inherit versionInfo;
      inherit (versionInfo) mainClass;
    });

  buildFabricClient = versionInfo: assetsIndex: fabricProfile: mods:
    let
      vanilla = buildVanillaClient versionInfo assetsIndex;
      loaderVersion = fabricProfile.loader;
      loader = fabricLoaders.${loaderVersion};
      extraJavaLibraries = buildFabricLibraries
        (fabricProfile.libraries.client ++ loader.libraries);
      mainClass = loader.mainClass.client;
      arguments = buildArguments versionInfo assetsIndex;
    in launchScript {
      inherit mainClass versionInfo mods;
      inherit (arguments) assets nativeLibraries;
      javaLibraries = arguments.javaLibraries ++ extraJavaLibraries;
    } // {
      withMods = extraMods:
        buildFabricClient versionInfo assetsIndex fabricProfile
        (mods ++ extraMods);
    };

  buildMc = versionInfo: assetsIndex: fabricProfile:
    let
      fabric = {
        client = buildFabricClient versionInfo assetsIndex fabricProfile [ ];
      };
    in {
      vanilla.client = buildVanillaClient versionInfo assetsIndex;
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
