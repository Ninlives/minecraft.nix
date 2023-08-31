{ config, lib, pkgs, ... }:
let
  inherit (lib.types) mkOptionType listOf package singleLineStr bool nullOr;
  inherit (lib.options) mergeEqualOption mkOption;
  inherit (lib.strings)
    isCoercibleToString hasSuffix concatStringsSep optionalString;
  inherit (pkgs) writeShellScriptBin;
  jarPath = mkOptionType {
    name = "jarFilePath";
    check = x:
      isCoercibleToString x && builtins.substring 0 1 (toString x) == "/"
      && hasSuffix ".jar" (toString x);
    merge = mergeEqualOption;
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
    mainClass = mkOption {
      type = nullOr singleLineStr;
      visible = false;
      default = null;
    };
    mainJar = mkOption {
      type = jarPath;
      visible = false;
      readOnly = true;
    };
  };

  config = {
    launchScript.gameExecution = ''
      exec "${config.java}" \
        -cp '${concatStringsSep ":" config.libraries.java}' \
        ${
          optionalString (config.mods != [ ])
          "-Dfabric.addMods='${concatStringsSep ":" config.mods}'"
        } \
        ${
          if config.mainClass != null then
            "${config.mainClass}"
          else
            "-jar '${config.mainJar}'"
        } \
        "''${runner_args[@]}"
    '';
    launcher =
      writeShellScriptBin "minecraft-server" config.launchScript.finalText;
  };
}
