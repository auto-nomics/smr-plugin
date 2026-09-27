# smr plugin

Migrated from the legacy `smr_heidi_container` wrapper in nodes-io. One
directory = one plugin family = one git-able unit.

## Layout

- `manifest.toml` — node kinds `smr_heidi` and `smr_heidi_eqtlgen`:
  params, ports, panels, image provenance
- `scripts/smr_heidi.sh` — Westra-panel execution script (kind
  `smr_heidi`)
- `scripts/smr_heidi_eqtlgen.sh` — eQTLGen-panel execution script (kind
  `smr_heidi_eqtlgen`)
- `Dockerfile` — image build tree, moved verbatim from
  `containers/smr/Dockerfile`; build with `test_smr_heidi.sh`
- `build_eqtlgen_besd.sh` — offline conversion of the eQTLGen full
  cis-eQTL release into the SMR BESD package published as
  `wjixiang/catalog-smr-eqtl-eqtlgen-hg19` (moved from
  `containers/smr/`, unchanged)
- `test_smr_heidi.sh` — image build/publish/digest-verify baseline;
  `root=` now points at this plugin directory and the catalog check
  takes the autonomics checkout via `AUTONOMICS_REPO_ROOT`

## The eqtl_source to two-node mapping

The legacy wrapper had one kind, `smr_heidi_container`, with an
`eqtl_source` spec enum (`westra` default, `eqtlgen` optional) that
selected which eQTL BESD panel was bound and mounted at
`/panels/smr_eqtl`. The v0 manifest DSL has no enum params and no
parameter-driven panel selection — family panels are static — so the
selection becomes two kinds in one plugin:

| legacy spec                                  | plugin kind          | script                        | eQTL BESD package                          | mount                      |
| -------------------------------------------- | -------------------- | ----------------------------- | ------------------------------------------ | -------------------------- |
| `eqtl_source = "westra"` (default, omitted)  | `smr_heidi`          | `scripts/smr_heidi.sh`        | `wjixiang/catalog-smr-eqtl-westra-hg19`    | `/panels/smr_eqtl_westra`  |
| `eqtl_source = "eqtlgen"`                    | `smr_heidi_eqtlgen`  | `scripts/smr_heidi_eqtlgen.sh`| `wjixiang/catalog-smr-eqtl-eqtlgen-hg19`   | `/panels/smr_eqtl_eqtlgen` |

Everything else about the two nodes is identical: same image, same LD
reference (`wjixiang/catalog-plink-ref-1000g-eur-binary` at the legacy
`/panels/smr_ld_ref` mount), same parameter set, same ports and output
contract (`smr.smr` format `smr_heidi`, `smr.log` format `smr_log`).

### Superset mounting

The manifest DSL supports family-level `[[panels]]` only, so both eQTL
panels mount on **both** nodes (plus the LD reference): three read-only
mounts per run, each at a distinct path. This is the ldsc-munge
superset precedent — the legacy munge wrapper also attached panels it
did not read. There is no conflict: the two BESD packages are distinct
immutable catalog bundles mounted at distinct paths, and each script
hard-codes exactly one `--beqtl-summary /panels/smr_eqtl_*/…` prefix.
The runtime cost is that running either node pulls/caches both eQTL
packages; the semantic behaviour is unchanged. If per-node panels
supersede this later, the eQTL panel pair is the thing to split.

## Params

All 14 non-selection params of the legacy `SmrHeidiContainerSpec` map
one-to-one (`chr`, `maf`, `peqtl_smr`, `peqtl_heidi`, `heidi_mtd`,
`heidi_min_m`, `heidi_max_m`, `ld_lower_limit`, `ld_upper_limit`,
`cis_wind_kb`, `max_num_ld`, `diff_freq`, `diff_freq_prop`,
`thread_num`), with the legacy `validate()` bounds expressed as
manifest `min`/`max`/`exclusive_min`/`exclusive_max`. `artifact_prefix`
and `timeout_secs` moved from params to node fields (plugin convention;
the legacy default prefix `/artifacts/smr_heidi_container` becomes the
kind-derived `/artifacts/smr_heidi` and `/artifacts/smr_heidi_eqtlgen`,
matching the suffix-less kinds).

Cross-field rules the DSL cannot express are enforced by the scripts
(coloc manifest precedent): `heidi_min_m <= heidi_max_m` (integer
`test`) and `ld_lower_limit < ld_upper_limit` (coreutils `sort -g`,
awk-free).

## Install

```sh
export AUTONOMICS_PLUGIN_ROOT=/mnt/projects/node-plugins
```

Enable `bundle-plugin` on the `data-engine` dependency and the runtime
picks this directory up at startup.

## Migration parity

The golden test
(`autonomics/crates/container-plugin/tests/smr_migration.rs`) compiles
both nodes and asserts image/outputs/panels/resources byte-exactly and
script markers semantically. Documented deltas:

- `peqtl_heidi` renders into env as serde_json's `0.0015654` where the
  legacy Rust `format!({e})` spelled `1.5654e-3`; equal after float
  parsing (pitfall 8).
- The legacy script interpolated `chr` via Rust string building
  (`--bfile …/1000G.EUR.QC.22`); the plugin scripts read `$SMR_CHR`.
- `--out /work/smr` becomes `--out "$AUTONOMICS_WORKDIR/smr"`; same
  path, plugin-convention spelling.
- `panel_bundles` is the three-panel superset above where the legacy
  compiled spec carried the two selected panels; each node still reads
  only its own BESD package.

Note: `containers/smr/fixtures/chr22.westra.ma` deliberately stays in
the autonomics checkout — the live Rust integration test
`nodes-io/tests/container_file_flow.rs`
(`real_catalog_backed_official_smr_heidi_eqtlgen_runs_with_container_backend`)
references it by relative path, and that test is removed only when the
legacy wrapper itself is deleted (see the migration checklist).
