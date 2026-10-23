# dns-as-code

Shared tooling for per-domain DNS repos: octoDNS reconciling a Hetzner DNS zone from
YAML, run from GitHub Actions so no local machine is needed. Each domain keeps its own
private repo, Hetzner project and tokens; only the tooling lives here.

## What is here

| Path | What it is |
| --- | --- |
| `flake.nix` | `packages.<system>.octodns`: octoDNS with the Hetzner provider, pinned through `flake.lock` |
| `.github/workflows/plan.yml` | Reusable workflow: validate, then dry-run `octodns-sync` with a read-only token |
| `docs/` | Spike findings and provider research carried over from kanerva.io |

## Using it from a domain repo

The domain repo's flake re-exports the package, so its own `flake.lock` pins the version:

```nix
inputs.dns-as-code = {
  url = "github:Tapiiri/dns-as-code";
  inputs.nixpkgs.follows = "nixpkgs";
};

# in outputs:
packages.x86_64-linux.octodns = dns-as-code.packages.x86_64-linux.octodns;
```

And calls the workflow:

```yaml
jobs:
  plan:
    uses: Tapiiri/dns-as-code/.github/workflows/plan.yml@main
    secrets:
      hetzner-token-ro: ${{ secrets.HETZNER_TOKEN_RO }}
```

`config/production.yaml` must set `backend: hcloud` on the Hetzner provider; the
provider's default points at the DNS API Hetzner removed in May 2026.
