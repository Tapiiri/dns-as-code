# Research: octodns-hetzner provider and Hetzner Cloud API support

**Date**: 2026-10-19 | **Researcher**: nw-researcher (Nova) | **Confidence**: High | **Sources**: 20

> STATUS: COMPLETE.

## Executive Summary

**The load-bearing assumption holds.** `octodns-hetzner` 2.0.0 exists (tag `v2.0.0`, 2026-02-12) and ships an explicit `hcloud` backend that talks to the Hetzner Cloud Zones API via the official `hcloud-python` client, which became a mandatory dependency in that release. This is confirmed by four mutually independent primary artifacts: PyPI metadata (`info.version: "2.0.0"`, `requires_dist` including `hcloud>=2.3.0`), the provider source itself (`__VERSION__ = '2.0.0'` plus `backend = kwargs.pop("backend", "dnsapi")` with a `dnsapi`/`hcloud` branch and a `ValueError` on anything else), the new `strategies.py` module (`DNSAPIStrategy`, `HCloudStrategy`), and nixpkgs pinning `v2.0.0` by signed tag. The one critical configuration detail: the default backend is still `dnsapi`, which targets the now-deleted Console API — **you must set `backend: hcloud` explicitly**, alongside a Hetzner **Cloud** token (not an old DNS token).

**nixpkgs does not lag, so the planned override is unnecessary.** nixpkgs-unstable and nixos-26.05 (the current stable; the question's "25.05 and 25.11" framing is one release behind) both carry 2.0.0; nixos-25.11 carries 1.0.0, which is dnsapi-only and therefore unusable. Two plan details are wrong on specifics: the package does **not** live at `pkgs/development/python-modules/octodns-hetzner/default.nix` (verified HTTP 404 on three channels) but at `pkgs/by-name/oc/octodns/providers/hetzner/package.nix`, and because `withProviders` composes via `python.withPackages ps`, any override must be injected into the Python package set (`pythonPackagesExtensions`) rather than applied to a top-level attribute. A concrete sketch is in Q3. The exact selector spelling for `withProviders` is the single item I could not verify remotely — see Gap G2 and the one-line `nix eval` check.

**Hetzner's shutdown is confirmed, and more precisely than "May 2026":** read-only on 2026-05-20, full removal of the Console and API on 2026-05-27 07:39 UTC, per Hetzner's own status page; the Cloud API replacement (`/v1/zones` + RRSets) has been GA since 2025-11-10, when new zone creation on the old system already stopped. **Three gotchas matter operationally.** (1) `SOA` is absent from `SUPPORTS` so it is invisible to octoDNS and needs no handling, but `SUPPORTS_ROOT_NS = True` means apex `NS` records *are* returned by `populate()` — omitting them from YAML plans a zone-breaking nameserver deletion; reject `NS` with a processor or carry the values in YAML. (2) `octodns-validate` in a commit hook with a dummy token is **safe**: neither `HetznerProvider.__init__` nor the hcloud client issues any request at construction, though the env var must be set to something non-empty, and `octodns-sync` must stay out of the hook because planning calls `populate()`. (3) TXT handling is the residual risk — keep `escaped_semicolons: true` (the default) and write `\;`, never hand-split long DKIM values (hcloud chunks automatically via `chunked_values`), and verify a second plan comes back empty, because the known perpetual-diff bug (#37) was closed "not planned" against the dnsapi backend and no source confirms the hcloud path is diff-stable.

## Research Methodology
**Search Strategy**: Primary sources first — github.com/octodns/octodns-hetzner (releases, tags, CHANGELOG, README, provider source), pypi.org/project/octodns-hetzner, nixpkgs source on GitHub, search.nixos.org, docs.hetzner.cloud / docs.hetzner.com. Blog posts only as corroboration.
**Source Selection**: official / technical_docs / industry_leaders (github.com)
**Quality Standards**: 3 sources/claim ideal; single authoritative primary source acceptable for version facts (PyPI/repo are definitive for their own metadata).

## Q1: Does octodns-hetzner 2.x exist, and does it support the Hetzner Cloud API?

**Answer: YES — verified. 2.0.0 exists and ships an explicit `hcloud` backend. The load-bearing assumption holds.**

### Finding 1.1: Latest release is 2.0.0 (tag v2.0.0, 2026-02-12)
**Evidence**: PyPI JSON API reports `info.version: "2.0.0"`, with release keys `0.0.1, 0.0.2, 1.0.0, 2.0.0`. The GitHub tags page shows `v2.0.0 — Feb 12, 2026`, `v1.0.0 — May 4, 2025`, `v0.0.2 — May 20, 2022`, `v0.0.1 — Jan 12, 2022` (all GPG-signed, tagger Ross McFarland).
**Source**: [PyPI JSON — octodns-hetzner](https://pypi.org/pypi/octodns-hetzner/json) — Accessed 2026-10-19; [GitHub tags](https://github.com/octodns/octodns-hetzner/tags) — Accessed 2026-10-19
**Confidence**: High (2 independent primary sources + source-tree confirmation below)
**Note**: PyPI `releases` has no `0.0.3` key although the CHANGELOG documents a v0.0.3 (ALIAS support) and the tags page does not show v0.0.3 either. Minor, immaterial to the decision.

### Finding 1.2: `hcloud` is a real backend, selected by a `backend:` provider key
**Evidence**: `octodns_hetzner/__init__.py` on `main` contains `__VERSION__ = '2.0.0'` and the lines:
```python
backend = kwargs.pop("backend", "dnsapi")
if backend == "hcloud":
...
elif backend == "dnsapi":
...
raise ValueError(f"Invalid backend '{backend}'. Must be 'dnsapi' or 'hcloud'")
```
It conditionally imports `HCloudZonesClient` (from `.hcloud_adapter`), `HetznerClient` (from `.dnsapi_client`), and `HCloudStrategy` / `DNSAPIStrategy` (from `.strategies`). `octodns_hetzner/strategies.py` exists and defines `ApplyStrategy` (Protocol), `DNSAPIStrategy`, `HCloudStrategy`.
**Source**: [raw `octodns_hetzner/__init__.py`](https://raw.githubusercontent.com/octodns/octodns-hetzner/main/octodns_hetzner/__init__.py), [raw `strategies.py`](https://raw.githubusercontent.com/octodns/octodns-hetzner/main/octodns_hetzner/strategies.py) — Accessed 2026-10-19
**Confidence**: High (provider source itself — the definitive artifact)

### Finding 1.3: Config keys — `backend:` and `token:`, no separate `api:` key
**Evidence**: README configuration example as retrieved:
```yaml
providers:
  hetzner:
    class: octodns_hetzner.HetznerProvider
    token: env/HETZNER_TOKEN
    backend: dnsapi
```
README documents the two options as "`dnsapi` (default): uses Hetzner DNS Console API" and "`hcloud`: uses Hetzner Cloud API (Zones)". `dnsapi` takes a DNS Console token; `hcloud` requires a Hetzner **Cloud** API token. The token is passed through the same `token:` key in both cases; the env var name in the example is `HETZNER_TOKEN` and is only a convention (octoDNS `env/` indirection), not enforced by the provider.
**Source**: [README](https://github.com/octodns/octodns-hetzner) / [raw README](https://raw.githubusercontent.com/octodns/octodns-hetzner/main/README.md) — Accessed 2026-10-19
**Confidence**: High for the `backend:`/`token:` keys (README + source code agree). **Medium** for the exact literal text of the YAML block: retrieved via summarizing fetch, see Knowledge Gap G1.
**Action for our config**: set `backend: hcloud` **explicitly**. The default is `dnsapi`, which talks to the now-defunct Console API — omitting the key silently targets the dead path.

### Finding 1.4: 2.0.0 CHANGELOG — hcloud via official hcloud-python, Strategy Pattern
**Evidence**: CHANGELOG `## 2.0.0 - 2026-02-12`, "Major: Add hcloud backend (mandatory dep) with Strategy Pattern refactoring — New `backend` parameter supports `dnsapi` (default) and `hcloud` options; hcloud backend uses Hetzner Cloud Zones API via official hcloud-python client (installed by default); Supports additional record types: DS, TLSA, PTR; ... No breaking changes - fully backward compatible - [#49]". Nearly all hcloud work traces to PR [#49](https://github.com/octodns/octodns-hetzner/pull/49); `list_zones` support came via [#47](https://github.com/octodns/octodns-hetzner/pull/47).
**Source**: [raw CHANGELOG.md](https://raw.githubusercontent.com/octodns/octodns-hetzner/main/CHANGELOG.md) — Accessed 2026-10-19
**Confidence**: Medium-High. See Knowledge Gap G1 — the retrieved CHANGELOG also attributed hcloud/Strategy-Pattern bullets to `v1.0.0 - 2025-05-04`, which contradicts both the 2.0.0 section and the dependency metadata. I judge the v1.0.0 hcloud bullets to be a retrieval artifact, not real; treat **2.0.0 as the first release with hcloud support**.

### Finding 1.5: hcloud is a hard dependency as of 2.0.0
**Evidence**: PyPI `info.requires_dist` for 2.0.0: `octodns>=1.5.0`, `requests>=2.27.0`, `hcloud>=2.3.0` (plus dev/test extras). hcloud is unconditional, not an extra — consistent with the CHANGELOG's "(mandatory dep)".
**Source**: [PyPI JSON](https://pypi.org/pypi/octodns-hetzner/json) — Accessed 2026-10-19
**Confidence**: High
**Analysis (interpretation, not sourced)**: The `hcloud>=2.3.0` floor looks too lax. Hetzner Cloud Zones only reached GA in Nov 2025 (see Q5), so the Zones API surface (`zone.get_rrset_all()`, `set_rrset_records()`, `change_rrset_ttl()`, `ZoneRecord`) cannot plausibly exist in hcloud 2.3.0. A resolver satisfying the floor with an old hcloud would fail at runtime, not install time. Pin a recent hcloud (nixpkgs currently has 2.26.0+; PyPI latest 2.27.0).

### Finding 1.6: Negative finding — no GitHub "Releases" entries
**Evidence**: `github.com/octodns/octodns-hetzner/releases` renders "There aren't any releases here."
**Source**: [GitHub releases](https://github.com/octodns/octodns-hetzner/releases) — Accessed 2026-10-19
**Confidence**: Medium
**Analysis**: This is **"verified absent" for GitHub Release objects only** — the project publishes signed git *tags* plus PyPI artifacts and a CHANGELOG, and does not create GitHub Releases. Do not read this as "no 2.x exists"; the tags page and PyPI contradict that. Practical consequence: do not build release automation or version detection around the GitHub Releases API for this repo; use tags or PyPI.

## Q2: What version does nixpkgs carry?

**Answer: nixpkgs-unstable and nixos-26.05 (current stable) carry 2.0.0. nixos-25.11 carries 1.0.0. No override is needed if you track unstable or 26.05.**

### Finding 2.1: Package path is the by-name octodns provider tree, not python-modules
**Evidence**: `pkgs/development/python-modules/octodns-hetzner/default.nix` returns **HTTP 404 on nixpkgs-unstable, nixos-25.11 and nixos-25.05** — the path assumed in the plan does not exist. The real location is `pkgs/by-name/oc/octodns/providers/hetzner/package.nix`. The directory `pkgs/by-name/oc/octodns/providers/` contains subdirectories: `bind, cloudflare, ddns, desec, gandi, hetzner, ovh, porkbun, powerdns, transip`.
**Source**: [nixpkgs providers dir](https://github.com/NixOS/nixpkgs/tree/master/pkgs/by-name/oc/octodns/providers) — Accessed 2026-10-19; 404s observed on the python-modules paths — Accessed 2026-10-19
**Confidence**: High (genuine HTTP 404 vs. successful retrieval at the by-name path)
**Consequence**: There is no top-level `python3Packages.octodns-hetzner` attribute at that path. The providers are built by `lib.packagesFromDirectoryRecursive` + `callPackage` inside the octodns package, so they are reached as `octodns.providers.*` / the provider set passed to `withProviders` — **not** via `python3Packages`. See Gap G2.

### Finding 2.2: Versions per channel
**Evidence**:

| Channel | version | src |
|---|---|---|
| `master` / nixpkgs-unstable | `2.0.0` | `fetchFromGitHub { owner="octodns"; repo="octodns-hetzner"; tag="v${version}"; hash="sha256-aWWT/LShHxWOfNhBr7vCeG9bA6yXEutO2NJic18szL8="; }` |
| `nixos-26.05` (current stable) | `2.0.0` | same hash `sha256-aWWT/LShHxWOfNhBr7vCeG9bA6yXEutO2NJic18szL8=` |
| `nixos-25.11` | `1.0.0` | hash `sha256-JYVztSO38y4F+p0glgtT9/QRdt9uDnOziMFXxBikzLg=` |
| `nixos-25.05` | not checked at by-name path (python-modules path 404) | — |

Master `package.nix`: `pname = "octodns-hetzner"`, `version = "2.0.0"`, build system `setuptools`, dependencies `octodns`, `requests`, `hcloud`; test inputs `pytestCheckHook`, `requests-mock`. Note it fetches from the **GitHub tag**, not PyPI.
**Source**: [master package.nix](https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/by-name/oc/octodns/providers/hetzner/package.nix), [nixos-26.05](https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-26.05/pkgs/by-name/oc/octodns/providers/hetzner/package.nix), [nixos-25.11](https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.11/pkgs/by-name/oc/octodns/providers/hetzner/package.nix) — Accessed 2026-10-19
**Confidence**: High (nixpkgs source tree is definitive for its own content)
**Channels that exist as of 2026-10-19**: 25.05 and 25.11 are past releases; **26.05 is the current stable**; 26.11 is not yet released. The question's framing ("25.05 and 25.11 if they exist") is a release behind.

### Finding 2.3: `withProviders` composes via `python.withPackages`
**Evidence**: `pkgs/by-name/oc/octodns/package.nix` defines `withProviders` in `passthru`; it takes a provider-selector function `ps`, and builds `let pyEnv = python.withPackages ps; in runCommand ...` which symlinks the octodns binaries out of that environment. Providers are discovered from `./providers` via `lib.packagesFromDirectoryRecursive`/`callPackage`.
**Source**: [octodns package.nix](https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/by-name/oc/octodns/package.nix) — Accessed 2026-10-19
**Confidence**: Medium-High (single primary source, retrieved via summarizing fetch)
**Attribute name**: The plan's `octodns.withProviders (ps: [ octodns-providers.hetzner ])` matches the documented nixpkgs usage pattern (an `octodns-providers` set referenced in nixpkgs docs/wiki and in nixpkgs PR traffic, e.g. [PR #569763](https://github.com/NixOS/nixpkgs/pull/569763) building `octodns-providers.hetzner`). Treat the exact spelling as **Medium confidence** — verify locally with `nix eval nixpkgs#octodns-providers.hetzner.version`. See Gap G2.

## Q3: Cleanest override if nixpkgs lags

**Answer: you probably do not need one.** On nixpkgs-unstable and nixos-26.05 the packaged version is already 2.0.0, which is the latest release (Finding 1.1 + 2.2). Only pin nixos-25.11 or older, which carries 1.0.0 (dnsapi-only).

### Finding 3.1: Where an override must be applied
**Evidence**: `withProviders` builds its environment with `python.withPackages ps` (Finding 2.3). The selector therefore resolves against the Python package set bound to the `octodns` derivation — not against the top-level `octodns-providers` attribute you reference in the selector list.
**Confidence**: Medium-High
**Consequence (interpretation)**: A bare `octodns-providers.hetzner.overrideAttrs {...}` at the top level will *not* reliably take effect, because `octodns.withProviders` re-resolves providers from its own Python set. The override must be injected into the Python package set itself. nixpkgs' canonical mechanism for that is `pythonPackagesExtensions`, which applies to every Python package set (3.11, 3.12, ...) at once.

### Recommended approach: `pythonPackagesExtensions` overlay + `fetchFromGitHub` tag

Matches how nixpkgs itself packages it (GitHub tag, not PyPI), so the version/tag/hash triple stays consistent and `pytestCheckHook` keeps working.

```nix
# flake.nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";

      overlay = final: prev: {
        pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
          (pyFinal: pyPrev: {
            octodns-hetzner = pyPrev.octodns-hetzner.overrideAttrs (old: rec {
              version = "2.0.0";
              src = final.fetchFromGitHub {
                owner = "octodns";
                repo  = "octodns-hetzner";
                tag   = "v${version}";
                # nixpkgs master hash for v2.0.0; re-derive if you bump version
                hash  = "sha256-aWWT/LShHxWOfNhBr7vCeG9bA6yXEutO2NJic18szL8=";
              };
              # 2.0.0 made hcloud a hard dep; floor in metadata is 2.3.0 but the
              # Zones API needs a recent client - take whatever nixpkgs has.
              dependencies = (old.dependencies or [ ]) ++ [ pyFinal.hcloud ];
            });
          })
        ];
      };

      pkgs = import nixpkgs { inherit system; overlays = [ overlay ]; };
    in {
      packages.${system}.octodns =
        pkgs.octodns.withProviders (ps: [ ps.octodns-hetzner ]);
    };
}
```

**Caveats to check locally** (I could not execute Nix): the exact selector spelling inside `withProviders` (`ps.octodns-hetzner` vs `ps.octodns-providers.hetzner`) and the attribute name in the Python set. Verify with:
```
nix eval nixpkgs#octodns-providers.hetzner.version
nix repl nixpkgs   # then: octodns.passthru.withProviders
```

### Option comparison

| Option | Verdict | Why |
|---|---|---|
| Just use nixpkgs-unstable / nixos-26.05 | **Recommended** | Already 2.0.0. Zero custom code, zero hash maintenance, tests run upstream. |
| `pythonPackagesExtensions` + `overrideAttrs` (above) | Recommended *if* pinned to 25.11 or needing an unreleased commit | Reuses nixpkgs' build (deps, patches, `pytestCheckHook`); only version/src change. Composes correctly with `withProviders`. |
| Top-level `octodns-providers.hetzner.overrideAttrs` | Avoid | Likely bypassed by `withProviders` re-resolving its own Python set. |
| `python3Packages.override { packageOverrides = ...; }` | Works but clumsy | Produces a *separate* package set; you must then rebuild `octodns` against it. More moving parts than the extension. |
| Fresh `buildPythonPackage` from PyPI (`fetchPypi`) | Avoid unless necessary | Duplicates dependency/test wiring that nixpkgs already maintains; diverges from upstream's GitHub-tag source, and the PyPI sdist may omit tests. |

## Q4: Known gotchas

### Finding 4.1: SOA is not managed at all; root NS *is* and must be in YAML
**Evidence**: Provider source declares
```python
SUPPORTS = set(("A", "AAAA", "CAA", "CNAME", "DS", "MX", "NS", "PTR", "SRV", "TLSA", "TXT",))
SUPPORTS_ROOT_NS = True
```
SOA is absent from `SUPPORTS`, and there is no special SOA handling in `populate()` or `_apply()`. Root NS support was added deliberately: issue [#6](https://github.com/octodns/octodns-hetzner/issues/6) "Root NS records fail to push to Hetzner" reported the warning `WARNING HetznerProvider[hetzner] root NS record not supported for <domain>.; ignoring it`, resolved by adding `SUPPORTS_ROOT_NS = True` (PR #7, modelled on the DigitalOcean provider). CHANGELOG v0.0.2 (2022-05-20) is titled "Root NS Support — Enable management of root NS records".
**Source**: [raw `__init__.py`](https://raw.githubusercontent.com/octodns/octodns-hetzner/main/octodns_hetzner/__init__.py), [issue #6](https://github.com/octodns/octodns-hetzner/issues/6), [CHANGELOG](https://raw.githubusercontent.com/octodns/octodns-hetzner/main/CHANGELOG.md) — Accessed 2026-10-19
**Confidence**: High (3 corroborating sources)
**Practical consequence**:
- **SOA**: never appears in plans, never needs YAML, cannot be managed. Hetzner's auto-created SOA is simply invisible to octoDNS. Nothing to exclude.
- **Root NS**: because `SUPPORTS_ROOT_NS = True`, `populate()` returns Hetzner's auto-created apex NS records. If your YAML omits the apex `NS`, octoDNS will plan a **delete of your zone's nameservers** — a zone-breaking change. Either (a) include the Hetzner apex NS values in YAML (dump them first, see 4.4), or (b) exclude the type from management on the target provider, e.g. a `SUPPORTS`/type filter or an `octodns.processor.filter.TypeAllowlistFilter` / `TypeRejectlistFilter` on `NS`. **Recommended for a Migadu setup: reject `NS` via a processor** so Hetzner keeps authority over its own nameservers and your YAML stays portable.

### Finding 4.2: TXT escaping — two distinct layers, and a known round-trip bug on the dnsapi backend
**Evidence**:
- octoDNS core: "RFCs require `\;` so octoDNS requires them in TXT records." The source-side `YamlProvider` exposes `escaped_semicolons` — "Whether or not `;` in values, e.g. TXT, need to be escaped `\;`" — **default `True`**.
- The dnsapi backend has a documented perpetual-diff bug: issue [#37](https://github.com/octodns/octodns-hetzner/issues/37) "Constant repplication of TXT records". Root cause per the investigation: *"The Hetzner API has a spurious space after the `"`, so when we drop the last character assuming it's a double-quote it's actually the space and that leaves the actual double quote."* Affects chunked (>255 char) TXT values such as DKIM. **Closed as "not planned"** (Oct 2024); the real fix was deemed to belong in octoDNS core's chunked-value parsing. Suggested workaround was a `.strip()` in the provider. Related: issue [#19](https://github.com/octodns/octodns-hetzner/issues/19) "DKIM - Invalid record" (closed, stale).
- The hcloud backend handles quoting explicitly in `hcloud_adapter.py`:
```python
def _quote_txt_value(self, value: str) -> str:
    """Wrap TXT record value in double quotes for hcloud API."""
    if value.startswith('"') and value.endswith('"'):
        return value
    escaped = value.replace('\\', '\\\\').replace('"', '\\"')
    return f'"{escaped}"'
```
and 2.0.0 fixed long-value handling by using `record.chunked_values` instead of `record.values` for hcloud TXT params, so ">255 chars are automatically split into RFC-compliant chunks".
**Source**: [issue #37](https://github.com/octodns/octodns-hetzner/issues/37), [raw `hcloud_adapter.py`](https://raw.githubusercontent.com/octodns/octodns-hetzner/main/octodns_hetzner/hcloud_adapter.py), [octoDNS YamlProvider API docs](https://octodns.readthedocs.io/en/stable/api/providers/octodns.provider.yaml.html), [CHANGELOG](https://raw.githubusercontent.com/octodns/octodns-hetzner/main/CHANGELOG.md) — Accessed 2026-10-19
**Confidence**: High for the mechanics; **Medium** for whether #37's spurious-diff behaviour is fully gone on the hcloud backend — #37 was filed against dnsapi and closed unfixed, and I found no issue confirming/denying recurrence under hcloud. See Gap G3.
**Practical consequence**:
- Keep `escaped_semicolons: true` (the default) in your `YamlProvider` and write SPF/DKIM/DMARC semicolons as `\;` in YAML. Migadu-style records (`v=spf1 include:spf.migadu.com -all`, DMARC `v=DMARC1\; p=...`) are exactly the affected shape.
- Do **not** hand-split long DKIM values into multiple `values:` entries — the README states *"Do not manually split long values into multiple `values:` entries unless you specifically need multiple distinct TXT records"*; hcloud chunking is automatic.
- After the first `octodns-sync --doit`, run a second plan. A clean no-op plan is your acceptance test that round-tripping is stable. If a TXT record re-appears in every plan, you are seeing the #37 class of bug.

### Finding 4.3: The provider does NOT contact the API at construction — `octodns-validate` with a dummy token is safe
**Evidence**: `HetznerProvider.__init__` is:
```python
def __init__(self, id, token, *args, **kwargs):
    self.log = logging.getLogger(f"HetznerProvider[{id}]")
    backend = kwargs.pop("backend", "dnsapi")
    self.log.debug("__init__: id=%s, token=***, backend=%s", id, backend)
    super().__init__(id, *args, **kwargs)
    self._backend = backend
    self._client = self._create_client(backend, token)
    self._strategy = self._create_strategy(backend)
    self._zone_records = {}
    self._zone_metadata = {}
    self._zone_name_to_id = {}
```
No request is issued; only client/strategy objects are built. The hcloud client is likewise inert at construction:
```python
def __init__(self, token: str):
    from hcloud import Client as HCloudClient  # lazy import
    self._hcloud = HCloudClient(token=token)
    self._zones = self._hcloud.zones
```
Network calls happen in `populate()` / `_apply()`.
**Source**: [raw `__init__.py`](https://raw.githubusercontent.com/octodns/octodns-hetzner/main/octodns_hetzner/__init__.py), [raw `hcloud_adapter.py`](https://raw.githubusercontent.com/octodns/octodns-hetzner/main/octodns_hetzner/hcloud_adapter.py) — Accessed 2026-10-19
**Confidence**: High (constructor source read directly, both layers)
**Practical consequence**: A commit hook running `octodns-validate` with `HETZNER_TOKEN=dummy` works — config/YAML validation instantiates providers but does not populate from the target. Caveats: (1) `token` is a **required positional-ish kwarg**, so the env var must be *set* (any non-empty value); an unset `env/HETZNER_TOKEN` fails at config load, not at the network. (2) Do **not** put `octodns-sync` (even without `--doit`) in the hook — a plan *does* call `populate()` and will hit the API and fail with a dummy token.

### Finding 4.4: `octodns-dump` fidelity
**Evidence**: No issue in the repo's full issue list (#6, #19, #27, #37, #48, #59, #63) concerns `octodns-dump` for this provider; **verified absent** rather than merely not found, since I enumerated every open and closed issue. Relevant indirect evidence: the dump path depends on `populate()`, and 2.0.0 fixed a significant hcloud `populate` bug — *"`_get_rrsets()` now calls `zone.get_rrset_all()` (correct hcloud API); previously checked non-existent `zone.rrsets` attribute, causing records to appear missing ... Fixes issue where root-level MX and TXT records were not fetched from the API"*. Also `list_zones` was added in 2.0.0 ([#47](https://github.com/octodns/octodns-hetzner/pull/47)) and "filters invalid/empty names", enabling dynamic zone config / `*` zone dumping.
**Source**: [issue list](https://github.com/octodns/octodns-hetzner/issues?q=is%3Aissue), [CHANGELOG](https://raw.githubusercontent.com/octodns/octodns-hetzner/main/CHANGELOG.md) — Accessed 2026-10-19
**Confidence**: Medium (negative finding + changelog inference; no direct dump-fidelity report)
**Practical consequence**: Use **2.0.0, not earlier**, for dumping — pre-fix hcloud populate silently omitted root-level MX and TXT, which for a Migadu zone is precisely the content you care about. Verify any dump by diffing a second `octodns-dump` and by checking apex MX/TXT are present before trusting it as your source of truth.

### Finding 4.5: Other notes
- **ALIAS appears to have been dropped from `SUPPORTS`.** v0.0.3 (2023-02-08) added "Support for `ALIAS` record types", but the current `SUPPORTS` set does not list ALIAS. Flagged as **unverified** as to intent (Gap G4). Immaterial for Migadu (CNAME/MX/TXT), but relevant if you wanted apex aliasing.
- **No dynamic records**: the README states the provider does not support dynamic records (weighted/geo). Fine for this use case.
- **TTL fallback is 3600** for the hcloud adapter ("Centralized TTL fallback (3600) for hcloud adapter"). Set TTLs explicitly in YAML to avoid surprise diffs; note `YamlProvider`'s own `default_ttl` is also 3600.
- **`mode` on zone creation**: 2.0.0 "Fix `zone_create()` to pass required `mode` parameter to hcloud API" — zone *creation* through the provider is new and only landed in 2.0.0. Prefer creating zones in the Hetzner Console and letting octoDNS manage records.
- **Token type matters**: `hcloud` needs a Hetzner **Cloud** API token (project-scoped, from Cloud Console), not an old DNS Console token. Old DNS tokens are dead along with the API (Q5).

## Q5 (side question): Was the standalone Hetzner DNS API shut down ~May 2026?

**Answer: YES — confirmed, with more precision than "May 2026". DNS now lives under the Cloud API with zone/RRSet endpoints.**

### Finding 5.1: Shutdown timeline
**Evidence**: Hetzner's status-page announcement is titled "Shutdown of DNS Console (dns.hetzner.com) in May 2026" and states *"As described in the documentation, the DNS Console is being shut down in May 2026."* Timeline as reported there:
- **2026-05-20** — old DNS Console & API entered **read-only** mode; all zones already migrated off the legacy system.
- **2026-05-27, 07:39 UTC** — DNS Console and API **completely removed**; `dns.hetzner.com` now redirects to `console.hetzner.com`.
**Source**: [status.hetzner.com incident c2146c42](https://status.hetzner.com/incident/c2146c42-6dd2-4454-916a-19f07e0e5a44) — Accessed 2026-10-19
**Confidence**: High (Hetzner's own status page — primary vendor source)

### Finding 5.2: DNS moved into the Cloud API as `/v1/zones` + RRSets
**Evidence**: Hetzner Cloud API changelog entries:
- **2025-10-07**: *"A new DNS API is now available in beta."*
- **2025-11-10**: *"DNS in Hetzner Console & the DNS API are now generally available. Creating zones under dns.hetzner.com is now no longer possible."*
- **2025-11-25**: *"We added a new action endpoint to the API: `POST /v1/zones/$ID_OR_NAME/rrsets/$RR_NAME/$RR_TYPE/actions/update_records"`*
**Source**: [docs.hetzner.cloud/changelog](https://docs.hetzner.cloud/changelog) — Accessed 2026-10-19
**Confidence**: High (vendor's own API changelog)
**Corroboration**: Independent downstream projects migrated for the same reason — octodns-hetzner issue [#48](https://github.com/octodns/octodns-hetzner/issues/48) "Migrate to the new Hetzner DNS API" (closed) and [#59](https://github.com/octodns/octodns-hetzner/issues/59) "Tag a release with the hcloud changes" (closed); also lego [#2743](https://github.com/go-acme/lego/issues/2743), certbot-dns-hetzner [#34](https://github.com/ctrlaltcoop/certbot-dns-hetzner/issues/34).
**Analysis**: The RRSet-shaped endpoint (`/v1/zones/{zone}/rrsets/{name}/{type}`) explains octodns-hetzner's 2.0.0 Strategy Pattern split: dnsapi was per-record CRUD, hcloud is per-RRSet. It also explains why TXT values must be fully quoted and chunked at the API boundary.
**Note on the plan's framing**: your plan says the DNS API was shut down in May 2026 — correct, but the *replacement* has been GA since **2025-11-10** and new zone creation on the old system stopped then. There was no window in which you could have used dnsapi for a fresh zone in 2026.

## Source Analysis

| Source | Domain | Reputation | Type | Access Date | Cross-verified |
|--------|--------|------------|------|-------------|----------------|
| PyPI JSON API — octodns-hetzner | pypi.org | High (1.0) | official index | 2026-10-19 | Y (tags, nixpkgs, source) |
| octodns-hetzner raw `__init__.py` | raw.githubusercontent.com | High (1.0) | primary source code | 2026-10-19 | Y (README, CHANGELOG) |
| octodns-hetzner raw `strategies.py` | raw.githubusercontent.com | High (1.0) | primary source code | 2026-10-19 | Y (CHANGELOG) |
| octodns-hetzner raw `hcloud_adapter.py` | raw.githubusercontent.com | High (1.0) | primary source code | 2026-10-19 | Y (CHANGELOG) |
| octodns-hetzner raw `CHANGELOG.md` | raw.githubusercontent.com | High (1.0) | primary | 2026-10-19 | Y (tags, PyPI) |
| octodns-hetzner README | github.com | Medium-High (0.8) | primary docs | 2026-10-19 | Y (source code) |
| octodns-hetzner tags page | github.com | Medium-High (0.8) | primary | 2026-10-19 | Y (PyPI) |
| octodns-hetzner releases page (negative) | github.com | Medium-High (0.8) | primary | 2026-10-19 | N (contradicted by tags/PyPI) |
| octodns-hetzner issues #6, #37, #48, #59, #63, #19 | github.com | Medium-High (0.8) | primary issue tracker | 2026-10-19 | Y |
| nixpkgs `providers/hetzner/package.nix` (master, 26.05, 25.11) | raw.githubusercontent.com | High (1.0) | primary source | 2026-10-19 | Y (3 channels) |
| nixpkgs `oc/octodns/package.nix` | raw.githubusercontent.com | High (1.0) | primary source | 2026-10-19 | N (single source) |
| nixpkgs issue #398191 / PR #569763 | github.com | Medium-High (0.8) | corroboration | 2026-10-19 | Y |
| Hetzner status page — DNS Console shutdown | status.hetzner.com | High (1.0) | vendor announcement | 2026-10-19 | Y (cloud changelog) |
| Hetzner Cloud API changelog | docs.hetzner.cloud | High (1.0) | vendor docs | 2026-10-19 | Y (status page) |
| octoDNS YamlProvider API docs | octodns.readthedocs.io | High (1.0) | official docs | 2026-10-19 | Y (octodns issues #66/#79) |
| PyPI JSON — hcloud | pypi.org | High (1.0) | official index | 2026-10-19 | Y (nixpkgs PRs) |

Reputation: High: 11 (69%) | Medium-High: 5 (31%) | Medium: 0 | Avg: **0.94**
Excluded domains encountered and not cited: `agentxcloud.com/blog`, `builtwith.com`, `lightrun.com`, `forums.apiscp.com` (appeared in search results; not used — blog/aggregator tier, and primary vendor sources were available).

## Knowledge Gaps

### Gap G1: Verbatim text of README and CHANGELOG could not be byte-exactly confirmed
**Issue**: All web retrieval in this session went through a summarizing fetch tool, so "quotes" are reconstructions rather than guaranteed byte-exact text. Critically, the retrieved CHANGELOG attributed hcloud/Strategy-Pattern bullets to **both** `2.0.0 (2026-02-12)` **and** `v1.0.0 (2025-05-04)`, which is internally inconsistent and contradicts `hcloud` being introduced as a new mandatory dependency in 2.0.0.
**Attempted**: raw.githubusercontent.com for README and CHANGELOG; PyPI JSON for dependency metadata; direct source files; tags page.
**Assessment**: The *substance* of Q1 is confirmed by four mutually independent artifacts (PyPI version + requires_dist, `__init__.py` `__VERSION__`/`backend` branching, `strategies.py` classes, nixpkgs 2.0.0 pin, issues #48/#59). I treat the v1.0.0 hcloud bullets as a retrieval artifact.
**Recommendation**: Before committing, run `curl -s https://raw.githubusercontent.com/octodns/octodns-hetzner/v2.0.0/README.md` and read the migration section directly. Low effort, removes the last doubt about exact config key spelling.

### Gap G2: Exact nixpkgs attribute path for `withProviders` selectors
**Issue**: I confirmed `withProviders` uses `python.withPackages ps` and that providers live at `pkgs/by-name/oc/octodns/providers/hetzner/package.nix`, but could not confirm whether the selector is written `ps: [ ps.octodns-hetzner ]` or `ps: [ octodns-providers.hetzner ]`, nor that a top-level `octodns-providers` attribute set exists with that exact name.
**Attempted**: nixpkgs by-name sources; directory listing; nixpkgs docs search; nixpkgs PR #569763 (which references building `octodns-providers.hetzner`, suggesting the attribute does exist).
**Recommendation**: Resolve in seconds locally: `nix eval --raw nixpkgs#octodns-providers.hetzner.version` (expect `2.0.0` on unstable). **This is the one thing in the plan I could not fully verify.**

### Gap G3: Whether the TXT perpetual-diff bug (#37) affects the hcloud backend
**Issue**: #37 was filed against the dnsapi backend and closed "not planned" in Oct 2024, with the root cause located in octoDNS core's chunked-value parsing. The hcloud backend uses a different quoting path (`_quote_txt_value` + `chunked_values`), and 2.0.0 contains several TXT fixes, but no source states whether round-tripping is now diff-stable.
**Attempted**: full enumeration of octodns-hetzner issues; CHANGELOG; hcloud_adapter source.
**Recommendation**: Empirical test — apply once, then re-plan and require an empty diff, specifically with a long DKIM value and a DMARC record containing `\;`.

### Gap G4: ALIAS support status
**Issue**: v0.0.3 added ALIAS; current `SUPPORTS` omits it. Cannot tell whether this is an intentional removal (Hetzner Cloud Zones may not offer ALIAS) or a retrieval omission. **Unverified.**
**Recommendation**: Irrelevant for Migadu; check only if apex aliasing is needed.

### Gap G5: nixos-25.05 provider version
**Issue**: Not determined. The python-modules path 404s and I did not query the by-name path on the 25.05 branch.
**Assessment**: Immaterial — 25.05 predates both the Cloud Zones GA and octodns-hetzner 2.0.0, so it cannot carry a usable version.

## Conflicting Information

### Conflict 1: Does octodns-hetzner have releases?
**Position A**: No releases exist — Source: [GitHub releases page](https://github.com/octodns/octodns-hetzner/releases), reputation 0.8, evidence: "There aren't any releases here".
**Position B**: Four releases exist, latest v2.0.0 (2026-02-12) — Sources: [GitHub tags](https://github.com/octodns/octodns-hetzner/tags) (GPG-signed tags v2.0.0/v1.0.0/v0.0.2/v0.0.1), [PyPI JSON](https://pypi.org/pypi/octodns-hetzner/json) (`info.version: "2.0.0"`), [nixpkgs](https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/by-name/oc/octodns/providers/hetzner/package.nix) (`version = "2.0.0"`, `tag = "v${version}"`, resolving hash).
**Assessment**: **Position B.** The project uses signed git tags + PyPI + CHANGELOG and does not create GitHub Release objects. nixpkgs successfully fetches `v2.0.0` by tag with a fixed-output hash, which is near-conclusive proof the tag exists. Position A is a true but narrow statement about GitHub Release objects only.

### Conflict 2: When was hcloud support introduced — 1.0.0 or 2.0.0?
**Position A**: 1.0.0 (2025-05-04), per retrieved CHANGELOG bullets under v1.0.0.
**Position B**: 2.0.0 (2026-02-12), per the 2.0.0 "Major" section describing it as a new feature with a **new mandatory dependency**, PR #49, plus issue #59 "Tag a release with the hcloud changes" (which only makes sense if hcloud work was unreleased before 2.0.0), plus nixos-25.11 shipping 1.0.0 while the Cloud API was already GA.
**Assessment**: **Position B**, high confidence. Also note hcloud Zones only reached GA 2025-11-10, six months *after* 1.0.0's release date — 1.0.0 could not have shipped support for an API that did not yet exist. Position A is almost certainly a retrieval artifact (Gap G1).

## Recommendations for Further Research
1. **Run the three local verification commands** (Gap G2, G1) before finalizing the flake — `nix eval nixpkgs#octodns-providers.hetzner.version`, `curl` the v2.0.0 README, and `nix repl` the `withProviders` signature. Converts the two Medium-confidence findings to High at trivial cost.
2. **Empirically test TXT round-trip stability** (Gap G3) on a throwaway zone with a long DKIM value and a `\;`-containing DMARC record. This is the highest residual risk for day-to-day noise in plans.
3. **Decide the root-NS policy explicitly** (Finding 4.1) — processor-based `NS` rejection vs. NS values in YAML. This is a zone-breaking footgun if left implicit.
4. **Pin hcloud explicitly** rather than relying on the `hcloud>=2.3.0` floor (Finding 1.5), which is too lax to guarantee a Zones-capable client.

## Full Citations
[1] Python Packaging Authority. "octodns-hetzner JSON metadata". PyPI. https://pypi.org/pypi/octodns-hetzner/json. Accessed 2026-10-19.
[2] octoDNS project. "octodns-hetzner — README". GitHub. https://github.com/octodns/octodns-hetzner. Accessed 2026-10-19.
[3] octoDNS project. "octodns-hetzner — CHANGELOG.md (main)". GitHub. https://raw.githubusercontent.com/octodns/octodns-hetzner/main/CHANGELOG.md. Accessed 2026-10-19.
[4] octoDNS project. "octodns_hetzner/__init__.py (main)". GitHub. https://raw.githubusercontent.com/octodns/octodns-hetzner/main/octodns_hetzner/__init__.py. Accessed 2026-10-19.
[5] octoDNS project. "octodns_hetzner/strategies.py (main)". GitHub. https://raw.githubusercontent.com/octodns/octodns-hetzner/main/octodns_hetzner/strategies.py. Accessed 2026-10-19.
[6] octoDNS project. "octodns_hetzner/hcloud_adapter.py (main)". GitHub. https://raw.githubusercontent.com/octodns/octodns-hetzner/main/octodns_hetzner/hcloud_adapter.py. Accessed 2026-10-19.
[7] octoDNS project. "Tags — octodns-hetzner". GitHub. https://github.com/octodns/octodns-hetzner/tags. Accessed 2026-10-19.
[8] octoDNS project. "Issues — octodns-hetzner". GitHub. https://github.com/octodns/octodns-hetzner/issues?q=is%3Aissue. Accessed 2026-10-19.
[9] "Root NS records fail to push to Hetzner". Issue #6, octodns-hetzner. GitHub. https://github.com/octodns/octodns-hetzner/issues/6. Accessed 2026-10-19.
[10] "Constant repplication of TXT records". Issue #37, octodns-hetzner. GitHub. https://github.com/octodns/octodns-hetzner/issues/37. Accessed 2026-10-19.
[11] NixOS. "pkgs/by-name/oc/octodns/providers/hetzner/package.nix (master)". nixpkgs. https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/by-name/oc/octodns/providers/hetzner/package.nix. Accessed 2026-10-19.
[12] NixOS. "pkgs/by-name/oc/octodns/providers/hetzner/package.nix (nixos-26.05)". nixpkgs. https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-26.05/pkgs/by-name/oc/octodns/providers/hetzner/package.nix. Accessed 2026-10-19.
[13] NixOS. "pkgs/by-name/oc/octodns/providers/hetzner/package.nix (nixos-25.11)". nixpkgs. https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.11/pkgs/by-name/oc/octodns/providers/hetzner/package.nix. Accessed 2026-10-19.
[14] NixOS. "pkgs/by-name/oc/octodns/package.nix (master)". nixpkgs. https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/by-name/oc/octodns/package.nix. Accessed 2026-10-19.
[15] Hetzner Online GmbH. "Shutdown of DNS Console (dns.hetzner.com) in May 2026". Hetzner Status. https://status.hetzner.com/incident/c2146c42-6dd2-4454-916a-19f07e0e5a44. Accessed 2026-10-19.
[16] Hetzner Online GmbH. "Changelog". Hetzner Cloud API Documentation. https://docs.hetzner.cloud/changelog. Accessed 2026-10-19.
[17] octoDNS project. "octodns.provider.yaml — octoDNS documentation". Read the Docs. https://octodns.readthedocs.io/en/stable/api/providers/octodns.provider.yaml.html. Accessed 2026-10-19.
[18] Python Packaging Authority. "hcloud JSON metadata". PyPI. https://pypi.org/pypi/hcloud/json. Accessed 2026-10-19.
[19] "octodns: `octodns.withProviders` fails to build". Issue #398191, nixpkgs. GitHub. https://github.com/NixOS/nixpkgs/issues/398191. Accessed 2026-10-19.
[20] "python3Packages.hcloud: 2.25.1 -> 2.26.0". PR #569763, nixpkgs. GitHub. https://github.com/NixOS/nixpkgs/pull/569763. Accessed 2026-10-19.

## Research Metadata
Researcher: nw-researcher (Nova) | Date: 2026-10-19 | Depth: detailed
Sources examined: ~24 | Cited: 20 | Cross-referenced claims: 11
Confidence distribution: High 70%, Medium-High/Medium 30%, Low 0%
Tool limitations: no shell/Nix evaluation available; all retrieval via summarizing web fetch (see Gap G1). Genuine HTTP 404s were distinguishable from retrieval failures and are reported as verified-absent where used.
Output: docs/research/toolchain/octodns-hetzner-hcloud-backend-research.md
