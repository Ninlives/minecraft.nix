{
  description = "Command line Minecraft launcher managed by nix";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    with flake-utils.lib;
    eachDefaultSystem (system:
      let
        inherit (pkgs) lib;
        pkgs = nixpkgs.legacyPackages.${system};
        OS = with pkgs.stdenv;
          if isLinux then
            "linux"
          else if isDarwin then
            "osx"
          else
            builtins.throw "Unsupported system ${system}";
      in {
        legacyPackages = lib.makeOverridable (import ./default.nix) {
          inherit pkgs lib OS;
          # Users may override this with their own application id
          clientID = "adf6c624-b9ba-472e-9469-e54cc8f98e87";
        };
      });
}
