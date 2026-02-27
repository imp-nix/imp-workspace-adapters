# imp-workspace-adapters

adapter/runtime repo for `imp.lib.mkWorkspaceFlakeOutputs` standalone mode

## flake

* aggregate: `github:imp-nix/imp-workspace-adapters`

## outputs

* `workspaceRuntime` (all adapters)
* `workspaceRuntimes.rust`
* `workspaceRuntimes.node`
* `workspaceRuntimes.python`
* `workspacePolicy`
* `workspaceAdapters`
* `monorepoAdapters`
* `lib.mkRuntime`
* `lib.monorepoAdapters`

## usage with imp-nix

```nix
inputs.imp.url = "github:imp-nix/imp-nix";
inputs.adapters.url = "github:imp-nix/imp-workspace-adapters";

outputs = { imp, adapters, ... }:
let
  delegated = imp.lib.mkWorkspaceFlakeOutputs {
    project = { ... };
    upstreamFlake = imp;
    runtime = adapters.workspaceRuntimes.rust;
  };
in
{ devShells = delegated.devShells; }
```
