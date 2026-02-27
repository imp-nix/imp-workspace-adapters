let
  resolvePkgsPath =
    {
      pkgs,
      pathText,
      label,
    }:
    let
      segments = pkgs.lib.splitString "." pathText;
    in
    if segments == [ ] || builtins.any (segment: segment == "") segments then
      throw "monorepo.rustAdapter: invalid pkgs path '${pathText}' for ${label}"
    else if !pkgs.lib.hasAttrByPath segments pkgs then
      throw "monorepo.rustAdapter: pkgs path '${pathText}' not found for ${label}"
    else
      pkgs.lib.attrByPath segments null pkgs;

  rustShellPackages =
    {
      project,
      policy,
      pkgs,
    }:
    let
      defaultPaths =
        if builtins.hasAttr "defaultShellPackages" policy.rust then
          policy.rust.defaultShellPackages
        else
          [ ];
      setNames = project.shellPackageSets or [ ];
      availableSets =
        if builtins.hasAttr "shellPackageSets" policy.rust then policy.rust.shellPackageSets else { };
      setPaths = builtins.concatLists (
        map (
          setName:
          if !builtins.hasAttr setName availableSets then
            throw "monorepo.rustAdapter: unknown rust shell package set '${setName}' for project '${project.name}'"
          else
            availableSets.${setName}
        ) setNames
      );
      projectPaths = project.shellPackages or [ ];
      packagePaths = pkgs.lib.unique (defaultPaths ++ setPaths ++ projectPaths);
    in
    map (
      pathText:
      resolvePkgsPath {
        inherit pkgs pathText;
        label = "rust workspace shell package";
      }
    ) packagePaths;

  resolveCargoEnv =
    {
      project,
      policy,
    }:
    let
      allFlags = project.cargoFlags;
    in
    policy.rust.baseCargoEnv
    // (
      if allFlags == [ ] then { } else { CARGO_BUILD_RUSTFLAGS = builtins.concatStringsSep " " allFlags; }
    );

  getCratePackage =
    {
      outputs,
      crate,
      profile,
      caller,
    }:
    if !builtins.hasAttr crate outputs then
      throw "${caller}: nci.outputs.${crate} not found"
    else
      let
        crateOutputs = outputs.${crate};
      in
      if !builtins.hasAttr "packages" crateOutputs then
        throw "${caller}: nci.outputs.${crate}.packages not found"
      else if !builtins.hasAttr profile crateOutputs.packages then
        throw "${caller}: nci.outputs.${crate}.packages.${profile} not found"
      else
        crateOutputs.packages.${profile};
in
{
  mkNciProject =
    {
      project,
      policy,
    }:
    let
      cargoEnv = resolveCargoEnv { inherit project policy; };
    in
    {
      path = project.path;
      export = project.export;
      drvConfig.env = cargoEnv;
      depsDrvConfig.env = cargoEnv;
    };

  applyShellTransform =
    {
      project,
      policy,
      pkgs,
      imp,
      shells,
    }:
    let
      extraShellPackages = rustShellPackages {
        inherit project policy pkgs;
      };
      aliasesToOverride = builtins.filter (alias: alias != project.workspace) project.aliases;
      shellsWithoutAliases = removeAttrs shells aliasesToOverride;
      transform = imp.mkWorkspaceShellTransform {
        workspace = project.workspace;
        aliases = aliasesToOverride;
        packages = extraShellPackages;
        shellHook = ''
          export CARGO_BUILD_BUILD_DIR=${policy.rust.sharedRootTarget}
        '';
      };
      applyTransform = transform {
        inherit pkgs;
        lib = pkgs.lib;
      };
    in
    applyTransform shellsWithoutAliases;

  getDefaultPackage =
    {
      project,
      config,
    }:
    let
      defaultPackage =
        if project.defaultPackage == null then
          throw "monorepo.rustAdapter.getDefaultPackage: project '${project.name}' has no defaultPackage"
        else
          project.defaultPackage;
    in
    getCratePackage {
      outputs = config.nci.outputs;
      crate = defaultPackage.crate;
      profile = defaultPackage.profile;
      caller = "monorepo.rustAdapter.getDefaultPackage(${project.name})";
    };
}
