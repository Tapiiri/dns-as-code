# dns-as-code

Shared tooling for per-domain DNS repos: octoDNS reconciling a Hetzner DNS zone from
YAML, run from GitHub Actions so no local machine is needed. Each domain keeps its own
private repo, Hetzner project and tokens; only the tooling lives here.

## What is here

| Path | What it is |
| --- | --- |
| `flake.nix` | `packages.<system>.octodns`: octoDNS with the Hetzner provider, pinned through `flake.lock` |
| `.github/workflows/plan.yml` | Reusable workflow: validate, dry-run `octodns-sync` with a read-only token, post the plan as a PR comment |
| `.github/workflows/apply.yml` | Reusable workflow: on a push to main, validate and `octodns-sync --doit` with the read-write token |
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

And calls the workflows: plan on pull requests (posted as a PR comment), apply on a
push to main.

```yaml
on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  plan:
    if: github.event_name != 'push'
    permissions:
      contents: read
      pull-requests: write
    uses: Tapiiri/dns-as-code/.github/workflows/plan.yml@main
    secrets:
      hetzner-token-ro: ${{ secrets.HETZNER_TOKEN_RO }}

  apply:
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    uses: Tapiiri/dns-as-code/.github/workflows/apply.yml@main
    secrets: inherit
```

| Secret | Where in the domain repo |
| --- | --- |
| `HETZNER_TOKEN_RO`, read-only | Repository secret |
| `HETZNER_TOKEN`, read and write | Environment secret in `production`, with deployments restricted to `main` |

The apply job runs one at a time per repo and refuses unless its commit is still the
tip of main, so DNS always converges on the newest main.

`config/production.yaml` must set `backend: hcloud` on the Hetzner provider; the
provider's default points at the DNS API Hetzner removed in May 2026.
