# Race Sui Smart Contract
> [!WARNING]
> This project is supposed to be used for Games that build on Race Protocol. It is also under development.

## Quick Start
The easiest way to get started is use [Nix](https://hydra.nixos.org/build/278148859/download/1/manual/installation/installing-binary.html) to set up the required toolchains. Suppose you have Nix installed, then just

``` console
$ nix develop
```

After that you will be in a nix shell with all the needed toolchains available on the command line.  We also add [Just](https://github.com/casey/just) command runner for convenience. For example, to build or publish the package:

``` console
$ just build

$ just publish
```

Use `just --list` or see Justfile` for all available recipes.
