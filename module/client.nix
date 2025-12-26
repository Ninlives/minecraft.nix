{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf versionAtLeast;
  inherit (lib.types) mkOptionType listOf path package singleLineStr bool str;
  inherit (lib.options) mergeEqualOption mkOption;
  inherit (lib.strings)
    isStringLike hasSuffix makeLibraryPath concatStringsSep concatMapStringsSep
    optionalString;
  inherit (pkgs) writeShellScriptBin jq linkFarmFromDrvs xorg;
  inherit (pkgs.writers) writePython3;
  jarPath = mkOptionType {
    name = "jarFilePath";
    check = x:
      isStringLike x && builtins.substring 0 1 (toString x) == "/"
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
  imports = [
    ./common/version.nix
    ./common/java.nix
    ./common/launch-script.nix
    ./common/files.nix
  ];

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
    jvmArgs = mkOption {
      type = listOf str;
      description = "List of extra arguments to pass (as prefix) to Java launcher";
      default = [];
    };
    appArgs = mkOption {
      type = listOf str;
      description = "List of extra arguments to pass (as postfix) to Java launcher";
      default = [];
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
  };

  config = {
    files."assets/indexes".source = "${config.assets.directory}/indexes";
    files."assets/objects".source = "${config.assets.directory}/objects";
    files."resourcepacks" = {
      source = linkFarmFromDrvs "resourcepacks" config.resourcePacks;
      recursive = !config.declarative;
    };
    files."shaderpacks" = {
      source = linkFarmFromDrvs "shaderpacks" config.shaderPacks;
      recursive = !config.declarative;
    };
    files."allowed_symlinks.txt".text = ''
      [prefix]/nix/store/
    '';

    launchScript = {
      preparation = {
        parseRunnerArgs = {
          deps = [ "parseArgs" ];
          text = ''
            XDG_DATA_HOME="''${XDG_DATA_HOME:-$HOME/.local/share}"
            PROFILE="$XDG_DATA_HOME/minecraft.nix/profile.json"

            mcargs=()
            function parse_runner_args() {
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
            }
            parse_runner_args "''${runner_args[@]}"
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
      # Minecraft versions before 1.13 use LWJGL2 for graphics, which determines
      # the existing graphics modes by parsing the output of the "xrandr" command.
      path = mkIf (!(versionAtLeast config.version "1.13")) [ xorg.xrandr ];
      gameExecution = let libPath = makeLibraryPath config.libraries.preload;
      in ''
        export LD_LIBRARY_PATH="${libPath}''${LD_LIBRARY_PATH:+':'}''${LD_LIBRARY_PATH:-}"
        exec "${config.java}" \
          ${builtins.concatStringsSep " " config.jvmArgs} \
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
          --userType "msa" \
          "''${mcargs[@]}" \
          ${builtins.concatStringsSep " " config.appArgs}
      '';
    };
    launcher = writeShellScriptBin "minecraft" config.launchScript.finalText;
  };
}
