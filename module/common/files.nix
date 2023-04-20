{ config, lib, pkgs, ... }:
let
  inherit (lib) mkOption filterAttrs concatMapStringsSep attrValues mkIf;
  inherit (lib.types) attrsOf bool nullOr path str submodule;
  inherit (pkgs) writeText;
  fileOptions = { config, name, ... }: {
    options = {
      name = mkOption {
        type = str;
        default = name;
        defaultText = "<name>";
      };
      enable = mkOption {
        type = bool;
        default = true;
        description = ''
          Wheater to link this file or directory.
        '';
      };
      text = mkOption {
        type = nullOr str;
        default = null;
        description = ''
          Text of the file. If this option is null then `file.<name>.source`
          must be set.
        '';
      };
      source = mkOption {
        type = path;
        description = ''
          Path to the source file or directory.
        '';
      };
      target = mkOption {
        type = str;
        default = name;
        defaultText = "<name>";
        description = ''
          Path to target file or directory.
        '';
      };
      recursive = mkOption {
        type = bool;
        default = false;
        description = ''
          Whether to link contents of the directory recursively instead of link the whole directory.
        '';
      };
    };
    config = {
      source = mkIf (config.text != null) (writeText name config.text);
    };
  };
  enabledFiles = filterAttrs (name: cfg: cfg.enable) config.files;
  link = f:
    if f.recursive then ''
      mkdir -p "${f.target}"
      lndir -silent "${f.source}" "${f.target}"
    '' else ''
      if [[ -e "${f.target}" ]]; then
        echo "Not linking ${f.name} because a file with same name already exists at ${f.target}."
        false # trigger error
      else
        mkdir -p $(dirname "${f.target}")
        ln -s "${f.source}" "${f.target}"
      fi
    '';
  checkAndLink = f: ''
    if [[ -L "${f.target}" ]] && [[ "$(realpath "${f.target}")" =~ ^${builtins.storeDir}/* ]]; then
      rm "${f.target}"
    fi
    ${link f}
  '';
in {
  options = {
    files = mkOption {
      type = attrsOf (submodule fileOptions);
      description = "Set files to link into the working directory.";
      default = { };
    };
  };
  config = {
    launch.prepare.linkFiles = {
      text = ''
        ${concatMapStringsSep "\n" checkAndLink (attrValues enabledFiles)}
      '';
      deps = [ "enterWorkingDirectory" ];
    };
    launch.path = with pkgs; [ xorg.lndir ];
  };
}
