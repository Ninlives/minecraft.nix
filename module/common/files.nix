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
      contents = mkOption {
        type = bool;
        default = false;
        description = ''
          Whether to link contents of the directory instead of linking the whole directory.
        '';
      };
      recursive = mkOption {
        type = bool;
        default = false;
        description = ''
          Whether to link contents of the directory *recursively* instead of linking the whole directory.
        '';
      };
    };
    config = {
      source = mkIf (config.text != null) (writeText name config.text);
    };
  };
  enabledFiles = filterAttrs (name: cfg: cfg.enable) config.files;

  # always convert boolean to non-empty string because we enabled the 'u' flag of bash
  # -u (treat unset variables as an error when substituting)
  boolToString = b: if b then "true" else "false";
in {
  options = {
    files = mkOption {
      type = attrsOf (submodule fileOptions);
      description = "Set files to link into the working directory.";
      default = { };
    };
  };
  config = {
    launchScript.preparation.linkFiles = {
      text = ''
        function checkAndLink {
          name=$1
          source=$2
          target=$3
          recursive=$4
          if [[ -L "$target" ]] && [[ "$(realpath "$target")" =~ ^${builtins.storeDir}/* ]]; then
            rm "$target"
          fi
          if [[ "$recursive" = "true" ]]; then
            mkdir -p "$target"
            lndir -silent "$source" "$target"
          else
            if [[ -e "$target" ]]; then
              echo "Not linking '$name' because a file with same name already exists at '$target'."
              false # trigger error
            else
              mkdir -p $(dirname "$target")
              ln -s "$source" "$target"
            fi
          fi
        }

        ${concatMapStringsSep "\n" (f:
          if f.contents then ''
            recursive="${boolToString f.recursive}"
            for path in "${f.source}"/*; do
              filename=$(basename "$path")
              name="${f.name}/$filename"
              source="$path"
              target="${f.target}/$filename"
              checkAndLink "$name" "$source" "$target" "$recursive"
            done
          '' else ''
            checkAndLink "${f.name}" "${f.source}" "${f.target}" "$recursive"
          '') (attrValues enabledFiles)}

        unset -f checkAndLink
      '';
      deps = [ "enterWorkingDirectory" ];
    };
    launchScript.path = with pkgs; [ xorg.lndir ];
  };
}
