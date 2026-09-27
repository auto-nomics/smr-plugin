#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: test_smr_heidi.sh

Builds and publishes the official SMR 1.4.2 image and verifies the Westra
BESD catalog package. The plugin now lives outside the autonomics
checkout; point AUTONOMICS_REPO_ROOT at the repo when using the catalog
check.

Environment:
  SMR_REGISTRY             Registry host (default 192.168.10.24:30500)
  SMR_LOCAL_IMAGE          Build tag (default localhost/atc/smr:1.4.2)
  SMR_IMAGE                Published tag (default $SMR_REGISTRY/atc/smr:1.4.2)
  SMR_DIGEST_REFERENCE     Immutable reference expected by the wrapper
  AUTONOMICS_REPO_ROOT     Autonomics checkout for the catalog check
                           (default /mnt/projects/autonomics_projects/autonomics)
  BUILD_IMAGE=0            Skip podman build
  PUSH_IMAGE=0             Skip registry push
EOF
}

# Plugin root: this directory (Dockerfile build context).
root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=${AUTONOMICS_REPO_ROOT:-/mnt/projects/autonomics_projects/autonomics}
registry=${SMR_REGISTRY:-192.168.10.24:30500}
local_image=${SMR_LOCAL_IMAGE:-localhost/atc/smr:1.4.2}
image=${SMR_IMAGE:-$registry/atc/smr:1.4.2}
digest_reference=${SMR_DIGEST_REFERENCE:-$registry/atc/smr@sha256:40c0db3c71eda506913c376ab939027fff8ce8eb55c262fd1e5da2fe4c351b6d}
build_image=${BUILD_IMAGE:-1}
push_image=${PUSH_IMAGE:-1}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && {
  usage
  exit 0
}

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

need cargo
need podman
need curl

export AUTONOMICS_PANEL_CACHE_ROOT=${AUTONOMICS_PANEL_CACHE_ROOT:-$HOME/.autonomics/panels}

catalog_json=$(cd "$repo_root" && cargo run -p data-catalog --bin autonomics-catalog -- \
  list --config ~/.autonomics/vfs.toml)
grep -q '"repo": "wjixiang/catalog-smr-eqtl-westra-hg19"' <<<"$catalog_json" || {
  echo "catalog current index is missing wjixiang/catalog-smr-eqtl-westra-hg19" >&2
  exit 1
}
grep -q '"repo": "wjixiang/catalog-plink-ref-1000g-eur-binary"' <<<"$catalog_json" || {
  echo "catalog current index is missing wjixiang/catalog-plink-ref-1000g-eur-binary" >&2
  exit 1
}

if [[ "$build_image" == 1 ]]; then
  podman build -f "$root/Dockerfile" \
    -t "$local_image" "$root"
  podman tag "$local_image" "$image"
elif [[ "$push_image" == 1 ]]; then
  podman tag "$local_image" "$image"
fi

if [[ "$push_image" == 1 ]]; then
  podman push --tls-verify=false "$image"
fi

actual_digest=$(curl -fsS \
  -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
  "http://$registry/v2/atc/smr/manifests/1.4.2" -D - -o /dev/null |
  tr -d '\r' | awk 'tolower($1)=="docker-content-digest:" {print $2}')
expected_digest=${digest_reference##*@}
[[ "$actual_digest" == "$expected_digest" ]] || {
  echo "published SMR digest mismatch: expected $expected_digest, got $actual_digest" >&2
  exit 1
}

help_text=$(podman run --rm --tls-verify=false "$image" --help 2>&1 || true)
grep -q 'Version 1.4.2 Linux' <<<"$help_text" || {
  echo "registry image is not running official SMR 1.4.2; got:" >&2
  echo "$help_text" >&2
  exit 1
}

echo "Official SMR container test completed successfully."
