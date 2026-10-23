# SPIKE findings — dns-as-code

Probe run Oct 19, 2026. Provider under test: `octodns-hetzner` 2.0.0 from nixpkgs-unstable
(store path `…-python3.14-octodns-hetzner-2.0.0`), `backend: hcloud`, octoDNS 1.15.0, Python 3.14.6.

Probe code: [`txt_roundtrip.py`](txt_roundtrip.py), kept as the reproducer for Finding 1.
It needs no credentials and no network. Run it inside a `python3.withPackages` env
containing `octodns-providers.hetzner`.

**Promoted on Oct 19, 2026** into the walking skeleton — see
[wave-decisions.md](wave-decisions.md).

## Assumption tested

> Does octodns-hetzner 2.0.0 on the `hcloud` backend round-trip a Hetzner zone to zero
> changes, and how do apex NS and escaped/chunked TXT values come through?

## Verdict: PARTIAL — mechanism confirmed, one empirical unknown remains

The provider works, the backend is real, and every claim the research reported from
summarised sources is now confirmed byte-exact against the installed source. One question
cannot be answered without a live zone, and it is the one that decides whether the
zero-change round trip is achievable at all. See **Blocked** below.

## Confirmed by reading the installed source

All line references are to `octodns_hetzner/` in the store path above.

- `backend = kwargs.pop("backend", "dnsapi")` (`__init__.py:65`). The default really is the
  removed API; `backend: hcloud` must be set explicitly. Invalid values raise
  `ValueError: Invalid backend '…'. Must be 'dnsapi' or 'hcloud'` (`__init__.py:113`).
- `SUPPORTS_ROOT_NS = True` (`__init__.py:46`) and `SOA` is absent from `SUPPORTS`
  (`__init__.py:47-61`). Apex NS records are returned by `populate()` and must be carried
  in YAML or rejected by a processor; SOA is invisible to octoDNS.
- **No request at construction.** `HetznerProvider.__init__` only builds a client and a
  strategy; `HCloudZonesClient.__init__` (`hcloud_adapter.py:31`) only constructs
  `hcloud.Client`. Verified empirically: the provider constructed with `token="dummy-token"`
  on the hcloud backend with no network access. `octodns-validate` in a commit hook is safe.
- `populate()` logs a warning and skips record types outside `SUPPORTS` (`__init__.py:319`),
  so unexpected types in Hetzner are silently ignored rather than failing.

## Finding 1 — TXT round-trip is asymmetric at the provider layer, but CLEAN end to end

> **CORRECTED Oct 20, 2026, after the first real sync.** This finding originally
> concluded that a quote-preserving API would cause a perpetual diff. That conclusion was
> **wrong**. The mechanism below is real, and Hetzner *does* store the quotes — verified
> against the API, which returns `'"hosted-email-verify=1dz5eiac"'` with literal quotes.
> But `just plan` reports **No changes**, because octoDNS's own `Record.new` strips
> surrounding quotes when it constructs a TXT record, absorbing the asymmetry.
>
> The probe was flawed: it called `provider._data_for_TXT(...)` directly and compared the
> returned dict against the YAML value. In the real flow `populate()` feeds that dict into
> `Record.new()`, which normalizes. The probe modelled the provider in isolation and
> skipped the layer that fixes it. Verified: `Record.new` turns
> `'"hosted-email-verify=1dz5eiac"'` into `'hosted-email-verify=1dz5eiac'`.
>
> **No processor or workaround is needed.** Escaped semicolons survive too: `_dmarc` stores
> `'"v=DMARC1; p=quarantine;"'` and round-trips to `v=DMARC1\; p=quarantine\;`.

The mechanism, which remains accurate:

The write path always quotes; the read path never unquotes. This is structural, not a
configuration choice:

- Write: `_params_for_TXT` uses `record.chunked_values` on the hcloud backend
  (`__init__.py:426-435`), then `_quote_txt_value` (`hcloud_adapter.py:203`) wraps anything
  not already quoted. `chunked_values` **always** adds quotes, even for short values.
- Read: `_data_for_TXT = _data_for_multiple` (`__init__.py:271`), whose only transform is
  `value.replace(";", "\\;")` (`__init__.py:162`). There is no dequoting step anywhere.

Measured, for our actual record set:

| YAML value | Sent to API | If API preserves quotes | If API strips quotes |
|---|---|---|---|
| `hosted-email-verify=abc123` | `"hosted-email-verify=abc123"` | **perpetual diff** | zero change |
| `v=spf1 include:spf.migadu.com -all` | `"v=spf1 include:spf.migadu.com -all"` | **perpetual diff** | zero change |
| `v=DMARC1\; p=quarantine\;` | `"v=DMARC1; p=quarantine;"` | **perpetual diff** | zero change |

So semicolon escaping is symmetric and correct — `\;` → `;` on write, `;` → `\;` on read —
and is **not** configurable at the provider level. (The plan previously said to keep an
`escaped_semicolons: true` provider default; no such provider option exists. The behaviour
is hardcoded.)

Everything therefore depends on whether the Hetzner Cloud API stores and returns TXT values
with the surrounding quotes. That is the blocked question.

## Finding 2 — WITHDRAWN: long TXT values round-trip fine

> **WITHDRAWN Oct 20, 2026.** This finding claimed TXT values over 255 characters could
> never round-trip cleanly. It rested on the same flawed model as Finding 1 — a crude
> `.strip('"')` instead of the real `Record.new` normalization.
>
> Re-tested properly: a 307-character value chunks to `"chunk1" "chunk2"`, and feeding that
> stored form back through `Record.new` reassembles it to the original 307 characters
> exactly. **Zero change.** octoDNS joins the chunks; there is no reassembly gap.
>
> Long TXT values are therefore supported. The remaining advice stands for a different
> reason: do not hand-split them, because `chunked_values` already does it correctly.

## Finding 3 — the `withProviders` selector has a dangerous near-miss

Gap G2 from the research is resolved, and the plan's spelling is correct:

| Expression | Result |
|---|---|
| `ps.octodns-hetzner` | `error: attribute 'octodns-hetzner' missing` — fails loudly, fine |
| `ps.hetzner` | **silently resolves to `python3.14-hetzner-0.8.3`**, the unrelated Hetzner Robot API client, and builds a broken env |
| `p.octodns-providers.hetzner` | correct — `octodns-providers.hetzner.version` = `2.0.0` |

The middle row is the trap: it evaluates without error and yields an environment with no
octoDNS provider at all. Use the fully-qualified top-level attribute, never `ps.hetzner`.

Note also that `octodns.withProviders` produces an environment exposing only the octoDNS
CLI binaries — there is no `python` on its `PATH`. Scripting against the provider needs
`python3.withPackages`, which the justfile does not need but a future probe might.

## Finding 4 — the Console zone-creation step is optional

`_apply` calls `self._client.zone_create(...)` when the zone does not exist
(`__init__.py:489-490`), and the hcloud adapter implements it with `mode="primary"` plus
`action.wait_until_finished()` for eventual consistency (`hcloud_adapter.py:145-189`).

So octoDNS can create the zone itself, with a read-write token. The plan lists "create the
zone in the Hetzner Console" as manual by design; that remains a legitimate choice, but it
is now a choice rather than a constraint. Worth keeping manual: zone creation with the
read-write token would otherwise happen implicitly during a `sync`, which is exactly the
kind of silent side effect the push-then-sync model exists to avoid.

## Finding 5 — TTL fallbacks can manufacture diffs

`zone_records_get` falls back to the zone TTL and then to a hardcoded `DEFAULT_TTL = 3600`
when an RRSet TTL is absent (`hcloud_adapter.py:19`, `:102-106`), and `zone_get` does the
same for the zone itself (`:85`). If Hetzner omits TTLs anywhere, dumped records will read
as 3600 regardless of the real value. Check TTLs explicitly in the first round trip rather
than trusting the dump.

Separately, `rrset_upsert` updates records and TTL in **two** API calls
(`hcloud_adapter.py:263-264`), so a TTL-only change is not atomic with a value change.

## RESOLVED — the blocked question is answered

**Does the Hetzner Cloud API return TXT values with the quotes the provider sends? Yes —
and it does not matter.** Settled Oct 20, 2026 by the first real sync: 10 records created,
then `just plan` reported `No changes` with 11 records found. Independently confirmed by
`dig @hydrogen.ns.hetzner.com`, which serves every record correctly.

The original procedure is kept below for the record, and for the next domain.

### Original procedure (no longer needed)

The remaining question is a single observation, not an investigation:

> **Does the Hetzner Cloud API return TXT values with the quotes the provider sends?**

It cannot be answered without a live zone. Prerequisites are all manual by design
(bootstrapping steps 1–2), and none exist yet: a Hetzner Console project for DNS, a
throwaway zone in it, and a read-only Cloud API token.

Once a token is available, the whole check is:

1. Create a throwaway zone in the DNS project.
2. Add one apex TXT record with value `v=DMARC1; p=quarantine;` in the Console.
3. `octodns-dump` the zone with `backend: hcloud` and the read-only token.
4. Look at the dumped YAML. Quotes around the value → Finding 1's bad branch, and the
   zero-change round trip is unreachable without a processor or an upstream fix. No quotes
   → the round trip works and the plan proceeds unchanged.
5. Also note how the apex NS records and their TTLs appear.
6. Delete the throwaway zone.

## Design implications

- `config/production.yaml` must set `backend: hcloud` explicitly. This is the single
  highest-consequence line in the repo.
- The flake must use `octodns-providers.hetzner`, never `ps.hetzner`.
- Pin nixpkgs to unstable or 26.05. nixos-25.11 carries 1.0.0, which is dnsapi-only.
- Apex NS needs an explicit decision — carry in YAML, or reject with a processor.
- Long TXT values are supported; `chunked_values` handles splitting and octoDNS reassembles.
- No TXT processor or workaround is needed. The provider-level quoting asymmetry is real but
  octoDNS normalizes it away.
