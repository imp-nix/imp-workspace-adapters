/**
  Python workspace adapter.

  Produces devShell/package/check outputs for `project.kind = "python-workspace"`.
*/
common:
{
  caller,
  project,
  runtime,
  ...
}:
let
  projectPath = common.requireProjectPath { inherit caller project; };
  nixpkgsInput = common.resolveNixpkgs { inherit runtime; };
  resolvedPolicy = common.resolvePolicy { inherit caller runtime; };
  systems = resolvedPolicy.systems;
  pythonPolicy = resolvedPolicy.python;
  moduleName = builtins.replaceStrings [ "-" ] [ "_" ] project.name;
in
{
  formatter = common.mkFormatter {
    inherit systems nixpkgsInput;
  };

  devShells = common.forAllSystems systems (
    system:
    let
      pkgs = import nixpkgsInput { inherit system; };
      python = common.getPolicyPackage {
        inherit caller pkgs;
        attrName = pythonPolicy.interpreterAttr;
        label = "python interpreter";
      };
      uv = common.getPolicyPackage {
        inherit caller pkgs;
        attrName = pythonPolicy.uvPackageAttr;
        label = "uv";
      };
    in
    {
      default = pkgs.mkShell {
        packages = [
          python
          uv
        ];
        shellHook = ''
          export UV_PROJECT_ENVIRONMENT="''${UV_PROJECT_ENVIRONMENT:-$PWD/${pythonPolicy.sharedVenvDir}/${project.name}}"
          export UV_LINK_MODE=copy
        '';
      };
    }
  );

  packages = common.forAllSystems systems (
    system:
    let
      pkgs = import nixpkgsInput { inherit system; };
      python = common.getPolicyPackage {
        inherit caller pkgs;
        attrName = pythonPolicy.interpreterAttr;
        label = "python interpreter";
      };
      uv = common.getPolicyPackage {
        inherit caller pkgs;
        attrName = pythonPolicy.uvPackageAttr;
        label = "uv";
      };
    in
    {
      default = pkgs.writeShellApplication {
        name = project.name;
        runtimeInputs = [
          python
          uv
        ];
        text = ''
          set -euo pipefail
          cd ${projectPath}
          export PYTHONPATH="${projectPath}/src''${PYTHONPATH:+:''${PYTHONPATH}}"
          exec uv run --no-project --no-managed-python --python ${python}/bin/python3 python -m ${moduleName} "$@"
        '';
      };
    }
  );

  checks = common.forAllSystems systems (
    system:
    let
      pkgs = import nixpkgsInput { inherit system; };
      python = common.getPolicyPackage {
        inherit caller pkgs;
        attrName = pythonPolicy.interpreterAttr;
        label = "python interpreter";
      };
      uv = common.getPolicyPackage {
        inherit caller pkgs;
        attrName = pythonPolicy.uvPackageAttr;
        label = "uv";
      };
    in
    {
      default =
        pkgs.runCommand "${project.name}-tests"
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
            cp -R ${projectPath} "$TMPDIR/project"
            chmod -R u+w "$TMPDIR/project"
            cd "$TMPDIR/project"
            export PYTHONPATH="$TMPDIR/project/src''${PYTHONPATH:+:''${PYTHONPATH}}"
            uv run --no-project --no-managed-python --python ${python}/bin/python3 python -m unittest discover -s tests -t .
            touch "$out"
          '';
    }
  );
}
