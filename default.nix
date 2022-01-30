{ pkgs ? import <nixpkgs> { }, lib ? pkgs.lib, clientID, OS ? "linux" }:
with lib;
let
  inherit (pkgs)
    fetchurl libpulseaudio libGL flite alsa-lib writeShellScript jq jre runCommand;
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
  libraryInfo = name:
    let
      inherit (fabricLibraries.${name}) repo hash;
      splitted = splitString ":" name;
      org = builtins.elemAt splitted 0;
      art = builtins.elemAt splitted 1;
      ver = builtins.elemAt splitted 2;
      path =
        "${replaceStrings [ "." ] [ "/" ] org}/${art}/${ver}/${art}-${ver}.jar";
      url = "${repo}/${path}";
      jar = fetchurl {
        inherit url;
        ${hash.type} = hash.value;
      };
    in { inherit path jar; };

  auth = writePython3 "checkAuth" {
    libraries = with pkgs.python3Packages; [ requests pyjwt colorama ];
    flakeIgnore = [ "E501" "E402" "W391" ];
  } ''
    ${builtins.replaceStrings ["@CLIENT_ID@"] [clientID] (builtins.readFile ./auth/msa.py)}
    ${builtins.readFile ./auth/login.py}
  '';
  checkAuthOpts = let
    json = "${jq}/bin/jq --raw-output";
    text = ''
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
    '';
  in concatMapStringsSep " \\\n"
  (t: "--run '${replaceStrings [ "'" ] [ "'\\''" ] t}'")
  (splitString "\n" text);

  generateWrapper = { mainClass, version, assetsIndex, mods ? [ ] }: ''
    makeWrapper ${jre}/bin/java $out/bin/minecraft \
        ${checkAuthOpts} \
        --add-flags "-Djava.library.path='$out/natives'" \
        --add-flags "-cp '$(find $out/libraries -name '*.jar' | tr -s '\n' ':')'" \
        ${
          optionalString (mods != [ ]) ''
            --add-flags "-Dfabric.addMods='$(find $out/mods -name '*.jar' | tr -s '\n' ':')'"''
        } \
        --add-flags "${mainClass}" \
        --add-flags "--version ${version}" \
        --add-flags "--assetsDir $out/assets" \
        --add-flags "--assetIndex ${assetsIndex}" \
        --add-flags '--uuid "$UUID"' \
        --add-flags '--accessToken "$ACCESS_TOKEN"' \
        --prefix LD_LIBRARY_PATH : "${libPath}"
  '';

  buildVanillaClient = versionInfo: assetsIndex:
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

    in pkgs.runCommand "minecraft-client-${versionInfo.id}" {
      buildInputs = [ pkgs.unzip pkgs.makeWrapper ];
      passthru.meta.mainProgram = "minecraft";
    } ''
      mkdir -p $out/bin $out/assets/indexes $out/libraries $out/natives
      ln -s ${client} $out/libraries/client.jar

      # Java libraries
      ${concatMapStringsSep "\n" (artif:
        let library = fetchurl { inherit (artif.downloads.artifact) url sha1; };
        in ''
          mkdir -p $out/libraries/${
            builtins.dirOf artif.downloads.artifact.path
          }
          ln -s ${library} $out/libraries/${artif.downloads.artifact.path}
        '') (filter (x: !(x.downloads ? "classifiers")) artifacts)}

      # Native libraries
      ${concatMapStringsSep "\n" (artif:
        let
          library = fetchurl {
            inherit (artif.downloads.classifiers.${artif.natives.${OS}})
              url sha1;
          };
        in ''
          unzip ${library} -d $out/natives && rm -rf $out/natives/META-INF
        '') (filter (x: (x.downloads ? "classifiers")) artifacts)}

      # Assets
      ${concatStringsSep "\n" (builtins.attrValues
        (flip mapAttrs assetsIndex.objects (name: a:
          let
            asset = fetchurl {
              sha1 = a.hash;
              url = "http://resources.download.minecraft.net/" + hashTwo;
            };
            hashTwo = builtins.substring 0 2 a.hash + "/" + a.hash;
          in ''
            mkdir -p $out/assets/objects/${builtins.substring 0 2 a.hash}
            ln -sf ${asset} $out/assets/objects/${hashTwo}
          '')))}
      ln -s ${builtins.toFile "assets.json" (builtins.toJSON assetsIndex)} \
          $out/assets/indexes/${versionInfo.assets}.json

      # Launcher
      ${generateWrapper {
        inherit (versionInfo) mainClass;
        version = versionInfo.id;
        assetsIndex = versionInfo.assets;
      }}
    '';

  buildFabricClient = versionInfo: assetsIndex: fabricProfile: mods:
    let
      vanilla = buildVanillaClient versionInfo assetsIndex;
      loaderVersion = fabricProfile.loader;
      loader = fabricLoaders.${loaderVersion};
      libraries = fabricProfile.libraries.client ++ loader.libraries;
      mainClass = loader.mainClass.client;
    in runCommand "${vanilla.name}-fabric" {
      buildInputs = [ pkgs.unzip pkgs.makeWrapper pkgs.xorg.lndir ];
      passthru.withMods = extraMods:
        buildFabricClient versionInfo assetsIndex fabricProfile
        (mods ++ extraMods);
      passthru.meta.mainProgram = "minecraft";
    } ''
      mkdir -p $out
      lndir -silent ${vanilla} $out

      # Java libraries
      ${concatMapStringsSep "\n" (lib:
        let inherit (libraryInfo lib) path jar;
        in ''
          mkdir -p $out/libraries/${builtins.dirOf path}
          ln -s ${jar} $out/libraries/${path}
        '') libraries}

      ${optionalString (mods != [ ]) ''
        mkdir -p $out/mods
        ${concatMapStringsSep "\n" (mod: "ln -s ${mod} $out/mods") mods}
      ''}

      # Launcher
      rm $out/bin/minecraft
      ${generateWrapper {
        inherit mainClass mods;
        version = versionInfo.id;
        assetsIndex = versionInfo.assets;
      }}
    '';

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
