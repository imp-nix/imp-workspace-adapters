/**
  Default workspace runtime policy.

  This file contains shared default config values used by adapter runtimes.
  Consumers can override any subtree by passing `policy = { ... }` to `mkRuntime`.
*/
{
  systems = [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ];

  rust = {
    defaultShellPackages = [
      "cargo-edit"
      "pkg-config"
      "openssl"
    ];

    shellPackageSets = {
      bevy = [
        "wayland"
        "libxkbcommon"
        "alsa-lib"
        "udev"
        "libx11"
        "libxcursor"
        "libxi"
        "libxrandr"
        "vulkan-loader"
        "vulkan-headers"
        "vulkan-tools"
        "vulkan-validation-layers"
      ];
    };
  };

  python = {
    interpreterAttr = "python3";
    uvPackageAttr = "uv";
    sharedVenvDir = ".venvs";
  };

  node = {
    interpreterAttr = "nodejs_22";
    defaultShellPackages = [ "nodePackages.pnpm" ];
  };
}
