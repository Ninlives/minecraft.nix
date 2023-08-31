{ lib, ... }: {
  options.version = lib.mkOption {
    type = lib.types.singleLineStr;
    readOnly = true;
  };
}
