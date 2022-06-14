{ pkgs ? import <nixpkgs> { }, lib ? pkgs.lib, authClientID, metadata, OS ? "linux" }:
with lib;
let
  extendedLib = lib.extend (import ./common.nix { inherit pkgs lib metadata; });
  client = import ./builder/client.nix {
    lib = extendedLib;
    inherit pkgs authClientID OS;
  };
  server = import ./builder/server.nix {
    lib = extendedLib;
    inherit pkgs;
  };
  manifests = metadata.manifests;
  convertVersion = v: "v" + replaceStrings [ "." " " ] [ "_" "_" ] v;
in mapAttrs' (gameVersion: assets: {
  name = convertVersion gameVersion;
  value = let
    clients = client.build gameVersion assets;
    servers = server.build gameVersion assets;
    notSupported = pkgs.writeShellScriptBin "notSupported" ''
      Fabric loader does not support game version "${gameVersion}".
    '';
  in {
    fabric.client = clients.fabric or notSupported;
    fabric.server = servers.fabric or notSupported;
    vanilla.client = clients.vanilla;
    vanilla.server = servers.vanilla;
  };
}) manifests
