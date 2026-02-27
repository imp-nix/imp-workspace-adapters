/**
  Monorepo adapter registry.

  These adapters are consumed by monorepo assembly pipelines that need
  project-kind-specific wiring for devshell transforms and outputs.
*/
{
  rustWorkspace = import ./rust_workspace.nix;
  nodeWorkspace = import ./node_workspace.nix;
  pythonWorkspace = import ./python_workspace.nix;
}
