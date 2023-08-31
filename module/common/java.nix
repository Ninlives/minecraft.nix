{ config, lib, pkgs, ... }: {
  options.java = lib.mkOption {
    type = lib.types.path;
    description = "Java executable to use.";
    default =
      # Accroding to https://help.minecraft.net/hc/en-us/articles/4409225939853-Minecraft-Java-Edition-Installation-Issues-FAQ
      # Java 8 is required to run Minecraft versions 1.12 through 1.17.
      # Java 17 is required to run Minecraft version 1.18 and up.
      if lib.versionAtLeast config.version "1.18" then
        "${pkgs.openjdk17}/bin/java"
      else
        "${pkgs.openjdk8}/bin/java";
    defaultText = ''
      if minecraft version >= 1.18
      then "''${openjdk17}/bin/java"
      else "''${openjdk8}/bin/java"
    '';
  };
}
