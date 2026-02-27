let
  getPolicyPackage =
    {
      pkgs,
      policy,
      attrName,
      label,
    }:
    if !builtins.hasAttr attrName pkgs then
      throw "monorepo.nodeAdapter: pkgs.${attrName} not found for ${label}"
    else
      pkgs.${attrName};

  getNode =
    {
      pkgs,
      policy,
    }:
    getPolicyPackage {
      inherit pkgs policy;
      attrName = policy.node.interpreterAttr;
      label = "nodejs interpreter";
    };

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
      throw "monorepo.nodeAdapter: invalid pkgs path '${pathText}' for ${label}"
    else if !pkgs.lib.hasAttrByPath segments pkgs then
      throw "monorepo.nodeAdapter: pkgs path '${pathText}' not found for ${label}"
    else
      pkgs.lib.attrByPath segments null pkgs;

  nodeShellPackages =
    {
      project,
      policy,
      pkgs,
    }:
    let
      defaultPaths =
        if builtins.hasAttr "defaultShellPackages" policy.node then
          policy.node.defaultShellPackages
        else
          [ ];
      projectPaths = project.shellPackages or [ ];
      packagePaths = pkgs.lib.unique (defaultPaths ++ projectPaths);
    in
    builtins.map (
      pathText:
      resolvePkgsPath {
        inherit pkgs pathText;
        label = "node workspace shell package";
      }
    ) packagePaths;

  assertAliasNamesAvailable =
    {
      project,
      shells,
    }:
    let
      conflicts = builtins.filter (alias: builtins.hasAttr alias shells) project.aliases;
    in
    if conflicts == [ ] then
      null
    else
      throw (
        "monorepo.nodeAdapter: aliases already defined for project '${project.name}': "
        + builtins.concatStringsSep ", " conflicts
      );

  projectFilePath =
    {
      project,
      fileName,
    }:
    "${project.path}/${fileName}";

  requireProjectFile =
    {
      project,
      fileName,
    }:
    let
      path = projectFilePath {
        inherit project fileName;
      };
    in
    if builtins.pathExists path then
      path
    else
      throw "monorepo.nodeAdapter: project '${project.name}' is missing ${fileName}";

  readProjectPackageJson =
    project:
    builtins.fromJSON (
      builtins.readFile (requireProjectFile {
        inherit project;
        fileName = "package.json";
      })
    );

  projectVersion =
    project:
    let
      packageJson = readProjectPackageJson project;
    in
    if !builtins.hasAttr "version" packageJson then
      "0.1.0"
    else if !builtins.isString packageJson.version || packageJson.version == "" then
      throw "monorepo.nodeAdapter: package.json version for project '${project.name}' must be a non-empty string"
    else
      packageJson.version;

  projectBinEntries =
    project:
    let
      caller = "monorepo.nodeAdapter(${project.name})";
      packageJson = readProjectPackageJson project;
      toBinEntry =
        name: script:
        if !builtins.isString name || name == "" then
          throw "${caller}: bin command name must be a non-empty string"
        else if !builtins.isString script || script == "" then
          throw "${caller}: bin command '${name}' must map to a non-empty script path"
        else
          {
            inherit name script;
          };
    in
    if !builtins.hasAttr "bin" packageJson then
      [
        {
          name = project.name;
          script = "dist/cli.js";
        }
      ]
    else if builtins.isString packageJson.bin then
      [ (toBinEntry project.name packageJson.bin) ]
    else if builtins.isAttrs packageJson.bin then
      builtins.map (commandName: toBinEntry commandName packageJson.bin.${commandName}) (
        builtins.attrNames packageJson.bin
      )
    else
      throw "${caller}: package.json 'bin' must be a string or an attrset";

  projectSource =
    {
      project,
      pkgs,
    }:
    pkgs.lib.cleanSourceWith {
      src = project.path;
      filter =
        path: type:
        let
          baseName = builtins.baseNameOf path;
        in
        pkgs.lib.cleanSourceFilter path type && baseName != "node_modules" && baseName != "dist";
    };

  projectNpmDeps =
    {
      project,
      pkgs,
    }:
    let
      _lockfilePath = requireProjectFile {
        inherit project;
        fileName = "package-lock.json";
      };
    in
    pkgs.importNpmLock {
      npmRoot = project.path;
    };

  buildWorkspaceNodeModules =
    {
      project,
      policy,
      pkgs,
    }:
    let
      node = getNode { inherit pkgs policy; };
      npmDeps = projectNpmDeps {
        inherit project pkgs;
      };
    in
    pkgs.buildNpmPackage {
      pname = "${project.name}-node-modules";
      version = projectVersion project;
      src = projectSource {
        inherit project pkgs;
      };
      nodejs = node;
      inherit npmDeps;
      npmConfigHook = pkgs.importNpmLock.npmConfigHook;
      dontNpmBuild = true;
      dontNpmInstall = true;
      dontNpmPrune = true;
      buildPhase = ''
        runHook preBuild
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        mkdir -p "$out"
        cp -R node_modules package.json package-lock.json "$out/"
        runHook postInstall
      '';
    };

  workspaceNodeModulesShellHook =
    {
      project,
      workspaceNodeModules,
    }:
    ''
      _monorepo_workspace_rel='workspaces/${project.workspaceDir}'
      _monorepo_workspace_dir=""
      _monorepo_workspace_node_modules=""
      _monorepo_current_target=""
      _monorepo_node_modules_source='${workspaceNodeModules}/node_modules'
      _monorepo_git_root=""
      if command -v git >/dev/null 2>&1; then
        _monorepo_git_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
      fi

      if [[ -n "$_monorepo_git_root" && -d "$_monorepo_git_root/$_monorepo_workspace_rel" ]]; then
        _monorepo_workspace_dir="$_monorepo_git_root/$_monorepo_workspace_rel"
      elif [[ -f "$PWD/package.json" ]]; then
        _monorepo_workspace_dir="$PWD"
      elif [[ -n "$_monorepo_git_root" && -f "$_monorepo_git_root/package.json" ]]; then
        _monorepo_workspace_dir="$_monorepo_git_root"
      fi

      if [[ -n "$_monorepo_workspace_dir" ]]; then
        _monorepo_workspace_node_modules="$_monorepo_workspace_dir/node_modules"
        if [[ -L "$_monorepo_workspace_node_modules" ]]; then
          _monorepo_current_target="$(readlink "$_monorepo_workspace_node_modules" || true)"
          if [[ "$_monorepo_current_target" != "$_monorepo_node_modules_source" ]]; then
            ln -sfn "$_monorepo_node_modules_source" "$_monorepo_workspace_node_modules"
          fi
        elif [[ ! -e "$_monorepo_workspace_node_modules" ]]; then
          ln -s "$_monorepo_node_modules_source" "$_monorepo_workspace_node_modules"
        fi
        export PATH="$_monorepo_workspace_node_modules/.bin''${PATH:+:$PATH}"
      fi

      export NODE_PATH="$_monorepo_node_modules_source''${NODE_PATH:+:$NODE_PATH}"
      unset _monorepo_workspace_rel _monorepo_workspace_dir _monorepo_workspace_node_modules _monorepo_current_target _monorepo_node_modules_source _monorepo_git_root
    '';

  buildProject =
    {
      project,
      policy,
      pkgs,
      pname,
      checkOnly ? false,
    }:
    let
      node = getNode { inherit pkgs policy; };
      npmDeps = projectNpmDeps {
        inherit project pkgs;
      };
      binEntries = projectBinEntries project;
      wrapperCommands = builtins.concatStringsSep "\n" (
        builtins.map (binEntry: ''
          makeWrapper ${node}/bin/node "$out/bin/${binEntry.name}" \
            --add-flags "$out/lib/${project.name}/${binEntry.script}"
        '') binEntries
      );
    in
    pkgs.buildNpmPackage {
      inherit pname;
      version = projectVersion project;
      src = projectSource {
        inherit project pkgs;
      };
      nodejs = node;
      inherit npmDeps;
      npmConfigHook = pkgs.importNpmLock.npmConfigHook;
      npmBuildScript = "build";
      doCheck = checkOnly;
      checkPhase =
        if checkOnly then
          ''
            runHook preCheck
            npm run test
            runHook postCheck
          ''
        else
          null;
      installPhase =
        if checkOnly then
          ''
            runHook preInstall
            touch "$out"
            runHook postInstall
          ''
        else
          ''
            runHook preInstall
            mkdir -p "$out/lib/${project.name}" "$out/bin"
            cp -R dist node_modules package.json package-lock.json "$out/lib/${project.name}/"
            ${wrapperCommands}
            runHook postInstall
          '';
      nativeBuildInputs = if checkOnly then [ ] else [ pkgs.makeWrapper ];
    };
in
{
  applyShellTransform =
    {
      project,
      policy,
      pkgs,
      shells,
    }:
    let
      conflictGuard = assertAliasNamesAvailable {
        inherit project shells;
      };
      workspaceNodeModules = buildWorkspaceNodeModules {
        inherit project policy pkgs;
      };
      workspaceShell = pkgs.mkShell {
        packages = [
          (getNode { inherit pkgs policy; })
        ]
        ++ (nodeShellPackages {
          inherit project policy pkgs;
        });
        inputsFrom = [ workspaceNodeModules ];
        shellHook = workspaceNodeModulesShellHook {
          inherit project workspaceNodeModules;
        };
      };
      aliasAttrs = builtins.listToAttrs (
        builtins.map (alias: {
          name = alias;
          value = workspaceShell;
        }) project.aliases
      );
    in
    builtins.seq conflictGuard (shells // { "${project.workspace}" = workspaceShell; } // aliasAttrs);

  packageAttrs =
    {
      project,
      policy,
      pkgs,
    }:
    {
      "${project.name}" = buildProject {
        inherit project policy pkgs;
        pname = project.name;
      };
    };

  checkAttrs =
    {
      project,
      policy,
      pkgs,
    }:
    let
      checkName = "${project.name}-tests";
    in
    {
      "${checkName}" = buildProject {
        inherit project policy pkgs;
        pname = checkName;
        checkOnly = true;
      };
    };
}
