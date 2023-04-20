{ config, lib, pkgs, ... }:
let
  inherit (lib.types) mkOptionType listOf path package singleLineStr bool;
  inherit (lib.options) mergeEqualOption mkOption;
  inherit (lib.strings)
    isCoercibleToString hasSuffix makeLibraryPath concatStringsSep
    concatMapStringsSep optionalString;
  inherit (pkgs) writeShellScriptBin jq jre linkFarmFromDrvs;
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
in {
  imports = [ ./common/launch-scripts.nix ./common/files.nix ];

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
    authClientID = mkOption {
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

  config = {
    files."assets".source = config.assets.directory;
    files."resourcepacks" = {
      source = linkFarmFromDrvs "resourcepacks" config.resourcePacks;
      recursive = !config.declarative;
    };
    files."shaderpacks" = {
      source = linkFarmFromDrvs "shaderpacks" config.resourcePacks;
      recursive = !config.declarative;
    };

    launch = {
      prepare = {
        parseRunnerArgs = {
          deps = [ "parseArgs" ];
          text = ''
            XDG_DATA_HOME="''${XDG_DATA_HOME:-~/.local/share}"
            PROFILE="$XDG_DATA_HOME/minecraft.nix/profile.json"

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
          '';
        };
        auth = let
          ensureAuth = writePython3 "ensureAuth" {
            libraries = with pkgs.python3Packages; [
              requests
              pyjwt
              colorama
              cryptography
            ];
            flakeIgnore = [ "E501" "E402" "W391" ];
          } ''
            ${builtins.replaceStrings [ "@CLIENT_ID@" ] [ config.authClientID ]
            (builtins.readFile ../auth/msa.py)}
            ${builtins.readFile ../auth/login.py}
          '';
        in {
          deps = [ "parseRunnerArgs" ];
          text = let json = "${jq}/bin/jq --raw-output";
          in ''
            ${ensureAuth} --profile "$PROFILE"

            UUID=$(${json} '.["id"]' "$PROFILE")
            USER_NAME=$(${json} '.["name"]' "$PROFILE")
            ACCESS_TOKEN=$(${json} '.["mc_token"]["__value"]' "$PROFILE")
          '';
        };
      };
      final = let libPath = makeLibraryPath config.libraries.preload;
      in ''
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
    };
    launcher = writeShellScriptBin "minecraft" config.launch.script;
  };
}
