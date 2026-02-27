/**
  Shared adapter helpers.

  These helpers are runtime-level primitives used by language adapters.
  They are intentionally independent of imp-nix and only depend on nixpkgs + policy.
*/
{
  nixpkgs,
  defaultPolicy,
  policy ? { },
}:
let
  effectivePolicy = {
    systems =
      if builtins.hasAttr "systems" policy then
        policy.systems
      else
        defaultPolicy.systems;
    rust = defaultPolicy.rust // (policy.rust or { });
    python = defaultPolicy.python // (policy.python or { });
    node = defaultPolicy.node // (policy.node or { });
  };

  forAllSystems =
    systems: f:
    builtins.listToAttrs (
      builtins.map (system: {
        name = system;
        value = f system;
      }) systems
    );
in
{
  inherit effectivePolicy forAllSystems;

  resolveNixpkgs =
    {
      runtime,
    }:
    if builtins.hasAttr "nixpkgs" runtime then runtime.nixpkgs else nixpkgs;

  resolvePolicy =
    {
      caller,
      runtime,
    }:
    let
      runtimePolicy =
        if !builtins.hasAttr "policy" runtime then
          effectivePolicy
        else if !builtins.isAttrs runtime.policy then
          throw "${caller}: runtime.policy must be an attrset"
        else
          runtime.policy;
    in
    {
      systems =
        if builtins.hasAttr "systems" runtimePolicy then
          runtimePolicy.systems
        else
          effectivePolicy.systems;
      rust = defaultPolicy.rust // (runtimePolicy.rust or { });
      python = defaultPolicy.python // (runtimePolicy.python or { });
      node = defaultPolicy.node // (runtimePolicy.node or { });
    };

  requireProjectPath =
    {
      caller,
      project,
    }:
    if builtins.hasAttr "path" project then
      project.path
    else
      throw "${caller}: standalone mode requires project.path (for example ./. in workspace flake)";

  resolvePkgsPath =
    {
      caller,
      pkgs,
      pathText,
      label,
    }:
    let
      segments = pkgs.lib.splitString "." pathText;
    in
    if segments == [ ] || builtins.any (segment: segment == "") segments then
      throw "${caller}: invalid pkgs path '${pathText}' for ${label}"
    else if !pkgs.lib.hasAttrByPath segments pkgs then
      throw "${caller}: pkgs path '${pathText}' not found for ${label}"
    else
      pkgs.lib.attrByPath segments null pkgs;

  getPolicyPackage =
    {
      caller,
      pkgs,
      attrName,
      label,
    }:
    if !builtins.hasAttr attrName pkgs then
      throw "${caller}: pkgs.${attrName} not found for ${label}"
    else
      pkgs.${attrName};

  resolveRustToolchain =
    {
      caller,
      pkgs,
    }:
    let
      rustToolchain = builtins.filter (pkg: pkg != null) [
        (if pkgs ? rustc then pkgs.rustc else null)
        (if pkgs ? cargo then pkgs.cargo else null)
        (if pkgs ? rustfmt then pkgs.rustfmt else null)
        (if pkgs ? clippy then pkgs.clippy else null)
      ];
    in
    if rustToolchain == [ ] then
      throw "${caller}: unable to resolve rust toolchain packages from nixpkgs"
    else
      rustToolchain;

  mkFormatter =
    {
      systems,
      nixpkgsInput,
    }:
    forAllSystems systems (
      system:
      let
        pkgs = import nixpkgsInput { inherit system; };
      in
      if pkgs ? nixfmt-tree then pkgs.nixfmt-tree else pkgs.nixfmt
    );
}
