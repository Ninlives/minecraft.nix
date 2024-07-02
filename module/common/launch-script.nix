{ config, pkgs, lib, ... }:

let
  cfg = config.launchScript;
  inherit (lib)
    mkOption attrNames mapAttrs textClosureMap id getBin isString
    concatMapStringsSep optionalString;
  inherit (lib.types) attrsOf listOf str lines submodule oneOf package bool;
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

  mkLaunchScript = preparation: gameExecution:
    let wrappedPreparation = mapAttrs wrapScriptSnippetEntry preparation;
    in ''
      #!${pkgs.runtimeShell}

      set -u # treat unset variables as an error when substituting

      _status=0
      trap "_status=1 _localstatus=\$?" ERR

      ${optionalString (!cfg.inheritPath) "export PATH="}
      ${concatMapStringsSep "\n" (p: ''export PATH="${mkPath p}:$PATH"'')
      cfg.path}

      ${textClosureMap id wrappedPreparation (attrNames wrappedPreparation)}

      if (( _status > 0 )); then
        RED='\033[0;31m'
        FIN='\033[0m'
        echo -e "''${RED}Refused to launch game.''${FIN}";
        exit $_status
      fi

      ${wrapScriptSnippet "gameExecution" gameExecution}

      # in case the final script does not perform exec
      exit $_status
    '';
in {
  options = {
    launchScript = {
      preparation = mkOption {
        type = attrsOf (submodule scriptOptions);
        description = "Set of preparation scripts.";
        default = { };
      };
      gameExecution = mkOption {
        type = lines;
        description = ''
          Script to execute the game. Typically `exec java ...`.

          If errors happened in launch scripts, this script will not be run.
        '';
      };
      inheritPath = mkOption {
        type = bool;
        default = false;
        description = ''
          Whether to inherit the PATH environment variable from parent process.
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
      finalText = mkOption {
        type = lines;
        readOnly = true;
        default = mkLaunchScript (cfg.preparation) (cfg.gameExecution);
        description = ''
          Final script text generated.
        '';
      };
    };
  };
  config = {
    # common launch scripts
    launchScript.preparation = {
      parseArgs.text = ''
        WORK_DIR="$PWD"
        runner_args=()

        while [[ "$#" -gt 0 ]];do
          case "$1" in
            --gameDir)
              shift
              WORK_DIR="$1"
              shift
              ;;
            *)
              runner_args+=("$1")
              shift
              ;;
          esac
        done
      '';
      enterWorkingDirectory = {
        deps = [ "parseArgs" ];
        text = ''
          cd "$WORK_DIR"
        '';
      };
    };
    launchScript.path = with pkgs; [ coreutils ];
  };
}
