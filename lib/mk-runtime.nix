/**
  Build a standalone workspace runtime.

  A runtime is consumed by `imp.lib.mkWorkspaceFlakeOutputs` in standalone mode.
*/
{
  nixpkgs,
  policy ? { },
  extraAdapters ? { },
  enabledKinds ? [
    "rust-workspace"
    "node-workspace"
    "python-workspace"
  ],
}:
let
  defaultPolicy = import ./policy.nix;
  common = import ./common.nix {
    inherit nixpkgs defaultPolicy policy;
  };
  adapterModules = import ./adapters.nix;

  selectedAdapterModules = builtins.listToAttrs (
    builtins.map (
      kind:
      if builtins.hasAttr kind adapterModules then
        {
          name = kind;
          value = adapterModules.${kind};
        }
      else
        throw "mkRuntime: unknown enabledKinds entry '${kind}'"
    ) enabledKinds
  );

  builtAdapters = builtins.mapAttrs (_kind: module: module common) selectedAdapterModules;
in
{
  inherit nixpkgs;
  policy = common.effectivePolicy;
  adapters = builtAdapters // extraAdapters;
}
