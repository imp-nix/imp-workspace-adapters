{
  description = "Workspace runtime adapters for imp-nix.";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      mkRuntime = import ./lib/mk-runtime.nix;
      monorepoAdapters = import ./monorepo/adapters;
      workspaceRuntime = mkRuntime {
        inherit nixpkgs;
      };
      workspaceRuntimes = {
        rust = mkRuntime {
          inherit nixpkgs;
          enabledKinds = [ "rust-workspace" ];
        };
        node = mkRuntime {
          inherit nixpkgs;
          enabledKinds = [ "node-workspace" ];
        };
        python = mkRuntime {
          inherit nixpkgs;
          enabledKinds = [ "python-workspace" ];
        };
      };
    in
    {
      lib = {
        inherit mkRuntime;
        inherit monorepoAdapters;
      };

      inherit workspaceRuntime workspaceRuntimes;
      workspacePolicy = workspaceRuntime.policy;
      workspaceAdapters = workspaceRuntime.adapters;
      inherit monorepoAdapters;
    };
}
