# minecraft.nix

Inspired by [this thread](https://discourse.nixos.org/t/minecraft-launcher-in-pure-nix-all-mc-versions/3937?u=ninlives), this flake contains derivations of both vanilla and fabric edition (if available) for all versions of minecraft.

(Old versions are not fully tested, feel free to file a issue if your encounter problems.)

# USAGE

## Run Client

```sh
$ nix run github:Ninlives/minecraft.nix#v1_18_1.vanilla.client
```

You will be asked to login before launch the game.
Only MSA login is supported, since Microsoft has started to migrate all Mojang accounts to Microsoft accounts.

## Run Server

```sh
$ nix run github:Ninlives/minecraft.nix#v1_18_1.vanilla.server
```

## Configuration

You may use the `withConfig` function to add extra configurations to the game:

```sh
{
  description = "A simple modpack.";
  inputs.minecraft.url = "github:Ninlives/minecraft.nix";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, minecraft, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system: {
      packages.minecraft-with-ae2 =
        (minecraft.legacyPackages.${system}.v1_18_1.fabric.client.withConfig [{
          mods = [
            (builtins.fetchurl {
              # file name must have a ".jar" suffix to be loaded by fabric
              name = "fabric-api.jar";
              url =
                "https://media.forgecdn.net/files/3609/610/fabric-api-0.46.1%2B1.18.jar";
              sha256 =
                "sha256:0d6dw9lsryy51by9iypcg2mk1p1ixf0bd3dblfgmv6nx8g98whlh";
            })
            (builtins.fetchurl {
              url =
                "https://media.forgecdn.net/files/3609/46/appliedenergistics2-10.0.0.jar";
              sha256 =
                "sha256:0v7nw98b22lbwyd5qy71w93rj7sh7ps30g4cb38s3g3n997yk49n";
            })
          ];
          # withConfig is also composable
        }]).withConfig {
          resourcePacks = [
            (builtins.fetchurl {
              url =
                "https://media.forgecdn.net/files/3577/971/Bare+Bones+1.18.zip";
              sha256 =
                "sha256:11a4d9rw0983y7jipir8gzsa2kpwl2p8jinx3gbh5lcy2a2pxzds";
            })
          ];
        };
    });
}
```

### Available Options

For client:

| Name | Description |
|------|-------------|
| **mods** | List of mods load by the game. |
| **resourcePacks** | List of resourcePacks available to the game. |
| **shaderPacks** | List of shaderPacks available to the game. The mod for loading shader packs should be add to option ``mods'' explicitly. |
| **authClientID** | The client id of the authentication application. |
| **declarative** | Whether using a declarative way to manage game files. Currently only resource packs and shader packs are managed. |

For server:

| Name | Description |
|------|-------------|
| **mods** | List of mods load by the game. |
| **declarative** | Whether using a declarative way to manage game files. No-op for server currently. |

# TODO

- [ ] Configure Minecraft and mods in nix
