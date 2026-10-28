# dns-as-code

Shared tooling for per-domain DNS repos: octoDNS reconciling a Hetzner DNS zone from
YAML, run from GitHub Actions so no local machine is needed. Each domain keeps its own
private repo, Hetzner project and tokens; only the tooling lives here.

## What is here

| Path | What it is |
| --- | --- |
| `flake.nix` | `packages.<system>.octodns`: octoDNS with the Hetzner provider, pinned through `flake.lock` |
| `.github/workflows/plan.yml` | Reusable workflow: validate, dry-run `octodns-sync` with a read-only token, post the plan as a PR comment |
| `.github/workflows/dump.yml` | Reusable workflow, run by hand: read a live zone from Hetzner and print it as YAML, for onboarding a zone that already has records |
| `.github/workflows/onboard.yml` | Reusable workflow, run by hand in a repo that manages no zones yet: dump a live zone, write its zone file and config, require a zero-change plan, push branch `onboard/<zone>` to open as a PR |
| `actions/apply/action.yml` | Composite action, used from the domain repo's own apply job: validate and `octodns-sync --doit` with the read-write token |
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

And calls them: the plan workflow on pull requests (posted as a PR comment), the apply
action on a push to main.

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
    uses: Tapiiri/dns-as-code/.github/workflows/plan.yml@<commit> # vX.Y.Z
    secrets:
      hetzner-token-ro: ${{ secrets.HETZNER_TOKEN_RO }}

  apply:
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: production
    concurrency:
      group: dns-apply
      cancel-in-progress: false
    steps:
      - uses: Tapiiri/dns-as-code/actions/apply@<commit> # vX.Y.Z
        with:
          hetzner-token: ${{ secrets.HETZNER_TOKEN }}
```

## Versions

Domain repos pin dns-as-code to a release's full commit SHA, with the version
as a comment, never `@main` and never a bare tag: the apply job holds the
read-write token, so what it runs changes only through a reviewed PR in the
domain repo. Inside this repo, third-party actions are pinned the same way.

To release: tag the commit `vX.Y.Z` here. To upgrade a domain repo: replace
the SHA and comment on every `Tapiiri/dns-as-code/...@` line in its
`.github/workflows/dns.yml`; its plan comment shows whether DNS would change.

Apply is an action, not a reusable workflow, because GitHub does not pass an
environment secret into a reusable workflow owned by another account. Declaring
the job in the domain repo reads `production` and its secret there.

| Secret | Where in the domain repo |
| --- | --- |
| `HETZNER_TOKEN_RO`, read-only | Repository secret |
| `HETZNER_TOKEN`, read and write | Environment secret in `production`, with deployments restricted to `main` |

The apply job runs one at a time per repo and refuses unless its commit is still the
tip of main, so DNS always converges on the newest main.

`config/production.yaml` must set `backend: hcloud` on the Hetzner provider; the
provider's default points at the DNS API Hetzner removed in May 2026.
