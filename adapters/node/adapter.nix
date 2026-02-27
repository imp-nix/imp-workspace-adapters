/**
  Node workspace adapter.

  Produces devShell/package/check outputs for `project.kind = "node-workspace"`.
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
  nodePolicy = resolvedPolicy.node;
  packageJson = builtins.fromJSON (builtins.readFile (projectPath + "/package.json"));
  version =
    if packageJson ? version && builtins.isString packageJson.version && packageJson.version != "" then
      packageJson.version
    else
      "0.1.0";
in
{
  formatter = common.mkFormatter {
    inherit systems nixpkgsInput;
  };

  devShells = common.forAllSystems systems (
    system:
    let
      pkgs = import nixpkgsInput { inherit system; };
      node = common.getPolicyPackage {
        inherit caller pkgs;
        attrName = nodePolicy.interpreterAttr;
        label = "nodejs interpreter";
      };
      defaultPaths = nodePolicy.defaultShellPackages or [ ];
      projectPaths = project.shellPackages or [ ];
      packagePaths = pkgs.lib.unique (defaultPaths ++ projectPaths);
      extraPackages = builtins.map (
        pathText:
        common.resolvePkgsPath {
          inherit caller pkgs pathText;
          label = "node workspace shell package";
        }
      ) packagePaths;
    in
    {
      default = pkgs.mkShell {
        packages = [ node ] ++ extraPackages;
      };
    }
  );

  packages = common.forAllSystems systems (
    system:
    let
      pkgs = import nixpkgsInput { inherit system; };
      node = common.getPolicyPackage {
        inherit caller pkgs;
        attrName = nodePolicy.interpreterAttr;
        label = "nodejs interpreter";
      };
      src = pkgs.lib.cleanSourceWith {
        src = projectPath;
        filter =
          path: type:
          let
            baseName = builtins.baseNameOf path;
          in
          pkgs.lib.cleanSourceFilter path type && baseName != "node_modules" && baseName != "dist";
      };
    in
    {
      default = pkgs.buildNpmPackage {
        pname = project.name;
        inherit version src;
        nodejs = node;
        npmDeps = pkgs.importNpmLock {
          npmRoot = src;
        };
        npmConfigHook = pkgs.importNpmLock.npmConfigHook;
        npmBuildScript = "build";
        doCheck = false;
        installPhase = ''
          runHook preInstall
          mkdir -p "$out"
          cp -R dist node_modules package.json package-lock.json "$out/"
          runHook postInstall
        '';
      };
    }
  );

  checks = common.forAllSystems systems (
    system:
    let
      pkgs = import nixpkgsInput { inherit system; };
      node = common.getPolicyPackage {
        inherit caller pkgs;
        attrName = nodePolicy.interpreterAttr;
        label = "nodejs interpreter";
      };
      src = pkgs.lib.cleanSourceWith {
        src = projectPath;
        filter =
          path: type:
          let
            baseName = builtins.baseNameOf path;
          in
          pkgs.lib.cleanSourceFilter path type && baseName != "node_modules" && baseName != "dist";
      };
    in
    {
      default = pkgs.buildNpmPackage {
        pname = "${project.name}-tests";
        inherit version src;
        nodejs = node;
        npmDeps = pkgs.importNpmLock {
          npmRoot = src;
        };
        npmConfigHook = pkgs.importNpmLock.npmConfigHook;
        npmBuildScript = "build";
        doCheck = true;
        checkPhase = ''
          runHook preCheck
          npm test
          runHook postCheck
        '';
        installPhase = ''
          runHook preInstall
          touch "$out"
          runHook postInstall
        '';
      };
    }
  );
}
