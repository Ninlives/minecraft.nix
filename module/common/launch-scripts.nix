{ config, pkgs, lib, ... }:

let
  cfg = config.launch;
  inherit (lib)
    mkOption attrNames mapAttrs textClosureMap id getBin isString
    concatMapStringsSep;
  inherit (lib.types) attrsOf listOf str lines submodule oneOf package;
  scriptOptions = {
    options = {
      deps = mkOption {
        type = listOf str;
        default = [ ];
        description = "List of script dependencies.";
      };
      text = mkOption {
        type = lines;
        description = "The content of the script.";
      };
    };
  };

  wrapScriptSnippet = name: text: ''
    #### Launch script snippet ${name}
    _localstatus=0
    printf "Run launch script snippet '%s'\n" "${name}"

    ${text}

    if (( _localstatus > 0 )); then
      RED='\033[0;31m'
      FIN='\033[0m'
      printf "''${RED}Launch script snippet '%s' failed (%s)''${FIN}\n" "${name}" "$_localstatus"
    fi
  '';

  wrapScriptSnippetEntry = name: entry:
    entry // {
      text = wrapScriptSnippet name entry.text;
    };

  mkPath = p: if isString p then p else "${getBin p}/bin";

  mkLaunchScript = prepareScripts: finalScript:
    let wrapped = mapAttrs wrapScriptSnippetEntry prepareScripts;
    in ''
      #!${pkgs.runtimeShell}

      set -u # treat unset variables as an error when substituting

      _status=0
      trap "_status=1 _localstatus=\$?" ERR

      export PATH=""
      ${concatMapStringsSep "\n" (p: ''export PATH="${mkPath p}:$PATH"'')
      cfg.path}

      ${textClosureMap id wrapped (attrNames wrapped)}

      if (( _status > 0 )); then
        RED='\033[0;31m'
        FIN='\033[0m'
        echo -e "''${RED}Refused to launch game.''${FIN}";
        exit $_status
      fi

      ${wrapScriptSnippet "final" finalScript}

      # in case the final script does not perform exec
      exit $_status
    '';
in {
  options = {
    launch = {
      prepare = mkOption {
        type = attrsOf (submodule scriptOptions);
        description = "Set of prepare scripts.";
        default = { };
      };
      final = mkOption {
        type = lines;
        description = ''
          Final script to run. Typically `exec java`.

          If errors happened in launch scripts, the final script will not be run.
        '';
      };
      path = mkOption {
        type = listOf (oneOf [ package str ]);
        default = [ ];
        description = ''
          Packages added to launch script's PATH environment variable.
          Only the bin directory will be added.
        '';
      };
      script = mkOption {
        type = lines;
        readOnly = true;
        default = mkLaunchScript (cfg.prepare) (cfg.final);
        description = ''
          Full script generated.
        '';
      };
    };
  };
  config = {
    # common launch scripts
    launch.prepare = {
      parseArgs.text = ''
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
      '';
      enterWorkingDirectory = {
        deps = [ "parseArgs" ];
        text = ''
          cd "$WORK_DIR"
        '';
      };
    };
    launch.path = with pkgs; [ coreutils ];
  };
}
