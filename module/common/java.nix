{ lib, ... }: {
  options.java = lib.mkOption {
    type = lib.types.path;
    description = "Java executable to use.";
  };
}
