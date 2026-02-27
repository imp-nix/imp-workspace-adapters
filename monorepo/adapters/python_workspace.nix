let
  getPolicyPackage =
    {
      pkgs,
      policy,
      attrName,
      label,
    }:
    if !builtins.hasAttr attrName pkgs then
      throw "monorepo.pythonAdapter: pkgs.${attrName} not found for ${label}"
    else
      pkgs.${attrName};

  getInterpreter =
    {
      pkgs,
      policy,
    }:
    getPolicyPackage {
      inherit pkgs policy;
      attrName = policy.python.interpreterAttr;
      label = "python interpreter";
    };

  getUv =
    {
      pkgs,
      policy,
    }:
    getPolicyPackage {
      inherit pkgs policy;
      attrName = policy.python.uvPackageAttr;
      label = "uv";
    };

  defaultModuleName = project: builtins.replaceStrings [ "-" ] [ "_" ] project.name;

  getWorkspaceShell =
    {
      project,
      policy,
      pkgs,
    }:
    let
      python = getInterpreter { inherit pkgs policy; };
      uv = getUv { inherit pkgs policy; };
    in
    pkgs.mkShell {
      packages = [
        python
        uv
      ];
      shellHook = ''
        					export UV_PROJECT_ENVIRONMENT="''${UV_PROJECT_ENVIRONMENT:-$PWD/${policy.python.sharedVenvDir}/${project.name}}"
        					export UV_LINK_MODE=copy
        				'';
    };

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
        "monorepo.pythonAdapter: aliases already defined for project '${project.name}': "
        + builtins.concatStringsSep ", " conflicts
      );

  packageName = project: project.name;
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
      workspaceShell = getWorkspaceShell {
        inherit project policy pkgs;
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
    let
      python = getInterpreter { inherit pkgs policy; };
      uv = getUv { inherit pkgs policy; };
      module = defaultModuleName project;
    in
    {
      "${packageName project}" = pkgs.writeShellApplication {
        name = packageName project;
        runtimeInputs = [
          python
          uv
        ];
        text = ''
          					set -euo pipefail
          					cd ${project.path}
          					export PYTHONPATH="${project.path}/src''${PYTHONPATH:+:''${PYTHONPATH}}"
          					exec uv run --no-project --no-managed-python --python ${python}/bin/python3 python -m ${module} "$@"
          				'';
      };
    };

  checkAttrs =
    {
      project,
      policy,
      pkgs,
    }:
    let
      python = getInterpreter { inherit pkgs policy; };
      uv = getUv { inherit pkgs policy; };
      checkName = "${project.name}-tests";
    in
    {
      "${checkName}" =
        pkgs.runCommand checkName
          {
            nativeBuildInputs = [
              python
              uv
            ];
          }
          ''
            				set -euo pipefail
            				export HOME="$TMPDIR/home"
            				mkdir -p "$HOME"
            				export UV_CACHE_DIR="$TMPDIR/uv-cache"
            				cp -R ${project.path} "$TMPDIR/project"
            				chmod -R u+w "$TMPDIR/project"
            				cd "$TMPDIR/project"
            				export PYTHONPATH="$TMPDIR/project/src''${PYTHONPATH:+:''${PYTHONPATH}}"
            				uv run --no-project --no-managed-python --python ${python}/bin/python3 python -m unittest discover -s tests -t .
            				touch "$out"
            			'';
    };
}
