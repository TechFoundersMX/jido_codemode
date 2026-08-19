{ pkgs, ... }:
{
  imports = builtins.filter builtins.pathExists [
    ./devenv.local.nix
  ];

  packages = with pkgs; [
    git
    nodejs
    sqlite
    beamMinimal27Packages.elixir_1_20
    beamMinimal27Packages.elixir-ls
  ];

  cachix.enable = false;

  env.ERL_AFLAGS = "-kernel shell_history enabled";

  processes.phoenix = {
    exec = "FORCE_COLOR=1 mix phx.server";
    process-compose.is_tty = true;
  };
}
