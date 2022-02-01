{ pkgs , lib ? pkgs.lib }: with lib; let inherit (pkgs) writeShellScriptBin; in {
  launchWrapper = { launchScript, resourcePacks ? [] }: writeShellScriptBin "minecraft" ''
    # <<<sh>>>
    WORK_DIR="$PWD"
    launch_args=()

    while [[ "$#" -gt 0 ]];do
      launch_args+=("$1")
      if [[ "$1" == "--gameDir" ]];then
        shift 1
        launch_args+=("$1")
        WORK_DIR="$1" 
      fi
      shift 1
    done

    pushd "$WORK_DIR"
    mkdir -p "$WORK_DIR/resourcepacks"
    # >>>sh<<<
    ${concatMapStringsSep "\n" (rp: let name = builtins.baseNameOf rp; in ''
        dest="$WORK_DIR/resourcepacks/${name}"
        if [[ -e "$dest" ]];then
          if [[ -L "$dest" ]] && [[ "$(realpath "$dest")" =~ ^${builtins.storeDir}/* ]];then
            rm "$dest"
            ln -s "${rp}" "$dest"
          else
            echo "Not linking $name because a file with same name already exists at $dest."
          fi
        else
          ln -s "${rp}" "$dest"
        fi
      '') resourcePacks}
    # <<<sh>>>

    ${launchScript} "''${launch_args[@]}"
    popd 
    # >>>sh<<<
  '';
}

