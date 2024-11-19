{ config, lib, pkgs, ... }:
let
  inherit (lib.types) mkOptionType listOf package singleLineStr bool nullOr str;
  inherit (lib.options) mergeEqualOption mkOption;
  inherit (lib.strings) isStringLike hasSuffix concatStringsSep optionalString;
  inherit (pkgs) writeShellScriptBin;
  jarPath = mkOptionType {
    name = "jarFilePath";
    check = x:
      isStringLike x && builtins.substring 0 1 (toString x) == "/"
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
        ${builtins.concatStringsSep " " config.jvmArgs} \
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
        "''${runner_args[@]}" \
        ${builtins.concatStringsSep " " config.appArgs}
    '';
    launcher =
      writeShellScriptBin "minecraft-server" config.launchScript.finalText;
  };
}
