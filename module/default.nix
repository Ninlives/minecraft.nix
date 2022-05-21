{ config, lib, pkgs, ... }:
let
  inherit (lib.types) mkOptionType listOf path package singleLineStr bool;
  inherit (lib.options) mergeEqualOption mkOption;
  inherit (lib.strings)
    isCoercibleToString hasSuffix makeLibraryPath concatMapStringsSep
    concatStringsSep optionalString;
  inherit (pkgs) writeShellScript writeShellScriptBin jq jre;
  inherit (pkgs.writers) writePython3;
  jarPath = mkOptionType {
    name = "jarFilePath";
    check = x:
      isCoercibleToString x && builtins.substring 0 1 (toString x) == "/"
      && hasSuffix ".jar" (toString x);
    merge = mergeEqualOption;
  };
  mkInternalOption = type:
    mkOption {
      inherit type;
      visible = false;
      readOnly = true;
    };

  auth = writePython3 "checkAuth" {
    libraries = with pkgs.python3Packages; [ requests pyjwt colorama ];
    flakeIgnore = [ "E501" "E402" "W391" ];
  } ''
    ${builtins.replaceStrings [ "@CLIENT_ID@" ] [ config.clientID ]
    (builtins.readFile ../auth/msa.py)}
    ${builtins.readFile ../auth/login.py}
  '';

  runnerScript = let
    json = "${jq}/bin/jq --raw-output";
    libPath = makeLibraryPath config.libraries.preload;
  in writeShellScript "minecraft" ''
    RED='\033[0;31m'
    FIN='\033[0m'
    PROFILE="$HOME/.local/share/minecraft.nix/profile.json"

    mcargs=()
    while [[ "$#" -gt 0 ]];do
      if [[ "$1" == "--launch-profile" ]];then
        shift 1
        if [[ "$#" -gt 0 ]];then
          PROFILE="$1"
        fi
      else
        mcargs+=("$1")
      fi
      shift 1
    done

    ${auth} --profile "$PROFILE" || { echo -e "''${RED}Refused to launch game.''${FIN}"; exit 1; }
    UUID=$(${json} '.["id"]' "$PROFILE")
    USER_NAME=$(${json} '.["name"]' "$PROFILE")
    ACCESS_TOKEN=$(${json} '.["mc_token"]["__value"]' "$PROFILE")

    # prepare assets directory
    mkdir assets
    ln -s ${config.assets.directory}/* assets/

    export LD_LIBRARY_PATH=${libPath}''${LD_LIBRARY_PATH:+':'}$LD_LIBRARY_PATH
    exec ${jre}/bin/java \
      -Djava.library.path='${
        concatMapStringsSep ":" (native: "${native}/lib")
        config.libraries.native
      }' \
      -cp '${concatStringsSep ":" config.libraries.java}' \
      ${
        optionalString (config.mods != [ ])
        "-Dfabric.addMods='${concatStringsSep ":" config.mods}'"
      } \
      ${config.mainClass} \
      --version "${config.version}" \
      --assetIndex "${config.assets.index}" \
      --uuid "$UUID" \
      --username "$USER_NAME" \
      --accessToken "$ACCESS_TOKEN" \
      "''${mcargs[@]}"
  '';

  launchScript = let
    checkAndLink = src: dest: ''
      # <<<sh>>>
      if [[ -e "${dest}" ]];then
        if [[ -L "${dest}" ]] && [[ "$(realpath "${dest}")" =~ ^${builtins.storeDir}/* ]];then
          rm "${dest}"
          ln -s "${src}" "${dest}"
        else
          echo "Not linking ${src} because a file with same name already exists at ${dest}."
        fi
      else
        ln -s "${src}" "${dest}"
      fi
      # >>>sh<<<
    '';
    preparePacks = dir: list: ''
      ${optionalString config.declarative ''rm -rf "${dir}"''}
      mkdir -p "${dir}"
      ${concatMapStringsSep "\n"
      (p: let name = builtins.baseNameOf p; in checkAndLink p "${dir}/${name}")
      list}
    '';
  in writeShellScriptBin "minecraft" ''
    # <<<sh>>>
    WORK_DIR="$PWD"
    runner_args=()

    while [[ "$#" -gt 0 ]];do
      runner_args+=("$1")
      if [[ "$1" == "--gameDir" ]];then
        shift 1
        runner_args+=("$1")
        WORK_DIR="$1" 
      fi
      shift 1
    done

    pushd "$WORK_DIR"
    # >>>sh<<<
    ${preparePacks "$WORK_DIR/resourcepacks" config.resourcePacks}
    ${preparePacks "$WORK_DIR/shaderpacks" config.shaderPacks}
    # <<<sh>>>

    ${runnerScript} "''${runner_args[@]}"
    popd 
    # >>>sh<<<
  '';

in {
  options = {
    # Interface
    mods = mkOption {
      type = listOf jarPath;
      description = "List of mods load by the game.";
      default = [ ];
    };
    resourcePacks = mkOption {
      type = listOf path;
      description = "List of resourcePacks available to the game.";
      default = [ ];
    };
    shaderPacks = mkOption {
      type = listOf path;
      description =
        "List of shaderPacks available to the game. The mod for loading shader packs should be add to option ``mods'' explicitly.";
      default = [ ];
    };
    clientID = mkOption {
      type = singleLineStr;
      description = "The client id of the authentication application.";
    };
    launcher = mkOption {
      type = package;
      description = "The launcher of the game.";
      readOnly = true;
    };
    declarative = mkOption {
      type = bool;
      description = "Whether using a declarative way to manage game files.";
      default = true;
    };

    # Internal
    libraries.java = mkOption {
      type = listOf jarPath;
      visible = false;
    };
    libraries.native = mkOption {
      type = listOf path;
      visible = false;
    };
    libraries.preload = mkOption {
      type = listOf package;
      visible = false;
    };
    assets.directory = mkInternalOption path;
    assets.index = mkInternalOption singleLineStr;

    mainClass = mkInternalOption singleLineStr;
    version = mkInternalOption singleLineStr;
  };

  config = { launcher = launchScript; };
}
