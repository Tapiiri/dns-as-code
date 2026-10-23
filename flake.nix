{
  description = "Shared tooling for per-domain DNS-as-code repos: octoDNS on Hetzner, run from GitHub Actions";

  inputs = {
    # Must be unstable or 26.05: nixos-25.11 carries octodns-hetzner 1.0.0,
    # which is dnsapi-only and cannot talk to the current Hetzner API.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = {nixpkgs, ...}: let
    lib = nixpkgs.lib;
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
  in {
    packages = forAllSystems (pkgs: rec {
      # `octodns-providers.hetzner` is the only correct spelling.
      # `ps.octodns-hetzner` fails loudly; `ps.hetzner` SILENTLY resolves to the
      # unrelated Hetzner Robot API client and yields an env with no provider.
      # See docs/spike-findings.md, Finding 3.
      octodns = pkgs.octodns.withProviders (_ps: [pkgs.octodns-providers.hetzner]);
      default = octodns;
    });

    formatter = forAllSystems (pkgs: pkgs.alejandra);
  };
}
