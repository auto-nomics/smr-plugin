set -eu

# Cross-field guard the v0 param DSL cannot express: the legacy wrapper
# validate() rejected heidi_min_m above heidi_max_m before building the
# script; the script owns the check now (coloc manifest precedent).
[ "$SMR_HEIDI_MIN_M" -le "$SMR_HEIDI_MAX_M" ] || {
  echo "heidi_min_m must not exceed heidi_max_m" >&2
  exit 1
}

# Float ordering guard, awk-free: sort -g (coreutils) orders decimal and
# e-notation values; duplicate lines mean equal limits, which the legacy
# wrapper validate() also rejected.
limits=$(printf '%s\n%s\n' "$SMR_LD_LOWER_LIMIT" "$SMR_LD_UPPER_LIMIT" | sort -g)
[ "$(printf '%s\n' "$limits" | sort -g -u | wc -l)" -eq 2 ] || {
  echo "ld_lower_limit and ld_upper_limit must differ" >&2
  exit 1
}
[ "$(printf '%s\n' "$limits" | head -n 1)" = "$SMR_LD_LOWER_LIMIT" ] || {
  echo "ld_lower_limit must be below ld_upper_limit" >&2
  exit 1
}

# Westra blood cis-eQTL GRCh37 BESD package (family panel binding
# smr_eqtl_westra). The sibling kind smr_heidi_eqtlgen reads the eQTLGen
# package instead; both mount side by side and never conflict.
smr \
  --bfile "/panels/smr_ld_ref/1000G.EUR.QC.$SMR_CHR" \
  --gwas-summary "$AUTONOMICS_INPUT0" \
  --beqtl-summary /panels/smr_eqtl_westra/westra_eqtl_hg19 \
  --chr "$SMR_CHR" \
  --maf "$SMR_MAF" \
  --peqtl-smr "$SMR_PEQTL_SMR" \
  --peqtl-heidi "$SMR_PEQTL_HEIDI" \
  --heidi-mtd "$SMR_HEIDI_MTD" \
  --heidi-min-m "$SMR_HEIDI_MIN_M" \
  --heidi-max-m "$SMR_HEIDI_MAX_M" \
  --ld-lower-limit "$SMR_LD_LOWER_LIMIT" \
  --ld-upper-limit "$SMR_LD_UPPER_LIMIT" \
  --cis-wind "$SMR_CIS_WIND_KB" \
  --max_num_ld "$SMR_MAX_NUM_LD" \
  --diff-freq "$SMR_DIFF_FREQ" \
  --diff-freq-prop "$SMR_DIFF_FREQ_PROP" \
  --thread-num "$SMR_THREAD_NUM" \
  --out "$AUTONOMICS_WORKDIR/smr" \
  > "$AUTONOMICS_OUTPUT1" 2>&1
test -s "$AUTONOMICS_OUTPUT0"
