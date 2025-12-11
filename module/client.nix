{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf versionAtLeast;
  inherit (lib.types) mkOptionType listOf path package singleLineStr bool;
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
    offlineMode = mkOption {
      type = bool;
      description = "Whether to run the game in offline mode.";
      default = false;
    };
    offlineUsername = mkOption {
      type = singleLineStr;
      description = "Username to use in offline mode.";
      default = "Player";
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
          in if config.offlineMode then ''
            # Offline mode: use provided username and generate a UUID
            USER_NAME="${config.offlineUsername}"
            # Generate a deterministic UUID based on the username
            UUID=$(python3 -c 'import uuid; print(str(uuid.uuid3(uuid.NAMESPACE_DNS, "offline:${config.offlineUsername}")).replace("-", ""))')
            ACCESS_TOKEN=""  # No access token in offline mode
            echo "Running in offline mode as user: $USER_NAME"
          '' else ''
            ${ensureAuth} --profile "$PROFILE"

            UUID=$(${json} '.["id"]' "$PROFILE")
            USER_NAME=$(${json} '.["name"]' "$PROFILE")
            # If profile is offline, ACCESS_TOKEN won't exist, so we provide empty string
            if [[ -n "$(${json} '.["offline"]' "$PROFILE" 2>/dev/null)" ]]; then
              ACCESS_TOKEN=""
            else
              ACCESS_TOKEN=$(${json} '.["mc_token"]["__value"]' "$PROFILE")
            fi
          '';
        };
      };
      # Minecraft versions before 1.13 use LWJGL2 for graphics, which determines
      # the existing graphics modes by parsing the output of the "xrandr" command.
      path = [ pkgs.python3 ] ++ lib.optional (!(versionAtLeast config.version "1.13")) xorg.xrandr;
      gameExecution = let libPath = makeLibraryPath config.libraries.preload;
      in ''
        export LD_LIBRARY_PATH="${libPath}''${LD_LIBRARY_PATH:+':'}''${LD_LIBRARY_PATH:-}"
        exec "${config.java}" \
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
          --userType "${if config.offlineMode then "mojang" else "msa"}" \
          "''${mcargs[@]}"
      '';
    };
    launcher = writeShellScriptBin "minecraft" config.launchScript.finalText;
  };
}
