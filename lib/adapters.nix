/**
  Adapter registry.

  Maps `project.kind` values to adapter builder modules.
*/
{
  "rust-workspace" = import ../adapters/rust/adapter.nix;
  "node-workspace" = import ../adapters/node/adapter.nix;
  "python-workspace" = import ../adapters/python/adapter.nix;
}
