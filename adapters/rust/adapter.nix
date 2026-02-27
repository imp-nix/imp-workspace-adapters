/**
  Rust workspace adapter.

  Produces devShell/check outputs for `project.kind = "rust-workspace"`.
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
  rustPolicy = resolvedPolicy.rust;
in
{
  formatter = common.mkFormatter {
    inherit systems nixpkgsInput;
  };

  devShells = common.forAllSystems systems (
    system:
    let
      pkgs = import nixpkgsInput { inherit system; };
      defaultPaths = rustPolicy.defaultShellPackages or [ ];
      availableSets = rustPolicy.shellPackageSets or { };
      setNames = project.shellPackageSets or [ ];
      setPaths = builtins.concatLists (
        builtins.map (
          setName:
          if !builtins.hasAttr setName availableSets then
            throw "${caller}: unknown rust shell package set '${setName}' for project '${project.name}'"
          else
            availableSets.${setName}
        ) setNames
      );
      projectPaths = project.shellPackages or [ ];
      packagePaths = pkgs.lib.unique (defaultPaths ++ setPaths ++ projectPaths);
      extraPackages = builtins.map (
        pathText:
        common.resolvePkgsPath {
          inherit caller pkgs pathText;
          label = "rust workspace shell package";
        }
      ) packagePaths;
      toolchain = common.resolveRustToolchain { inherit caller pkgs; };
    in
    {
      default = pkgs.mkShell {
        packages = toolchain ++ extraPackages;
      };
    }
  );

  packages = { };

  checks = common.forAllSystems systems (
    system:
    let
      pkgs = import nixpkgsInput { inherit system; };
      toolchain = common.resolveRustToolchain { inherit caller pkgs; };
      nativeBuildInputs =
        toolchain
        ++ (builtins.filter (pkg: pkg != null) [
          (if pkgs ? pkg-config then pkgs.pkg-config else null)
          (if pkgs ? openssl then pkgs.openssl else null)
        ]);
    in
    {
      default = pkgs.runCommand "${project.name}-tests" { inherit nativeBuildInputs; } ''
        set -euo pipefail
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        cp -R ${projectPath} "$TMPDIR/project"
        chmod -R u+w "$TMPDIR/project"
        cd "$TMPDIR/project"
        cargo test --workspace --all-targets
        touch "$out"
      '';
    }
  );
}
