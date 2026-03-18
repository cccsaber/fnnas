#!/bin/bash
set -euo pipefail

rootfs_dir="${FNNAS_TAG_ROOTFS_DIR:-}"
target_rel="usr/trim/bin/handlers/storage.hdl"
target=""

expected_orig_sha="6f903d218a0d2d9c04184ce4d552ed18e8b9fa3a329e04840353729fa6de3784"
expected_patched_sha="f97a12cb916fcf628a099cae2c9ed46565b410a1661f3636fc68719fcb2057b4"

offsets=(174848 177568 273296)
original_words=("012c0054" "e1110054" "412b0054")
nop_word="1f2003d5"

log() {
    printf '[h20plus] %s\n' "$*"
}

die() {
    printf '[h20plus] ERROR: %s\n' "$*" >&2
    exit 1
}

read_word() {
    local off="$1"
    od -An -tx1 -N4 -j "${off}" "${target}" | tr -d ' \n'
}

write_nop() {
    local off="$1"
    printf '\x1f\x20\x03\xd5' | dd of="${target}" bs=1 seek="${off}" conv=notrunc status=none
}

[[ -n "${rootfs_dir}" ]] || die "FNNAS_TAG_ROOTFS_DIR is not set"
target="${rootfs_dir}/${target_rel}"
[[ -f "${target}" ]] || die "Missing ${target_rel} in build rootfs"

current_sha="$(sha256sum "${target}" | awk '{print $1}')"
if [[ "${current_sha}" == "${expected_patched_sha}" ]]; then
    log "storage.hdl already patched"
    exit 0
fi

[[ "${current_sha}" == "${expected_orig_sha}" ]] || die "Unexpected storage.hdl sha256: ${current_sha}"

for idx in "${!offsets[@]}"; do
    current_word="$(read_word "${offsets[$idx]}")"
    [[ "${current_word}" == "${original_words[$idx]}" ]] ||
        die "Unexpected word at offset ${offsets[$idx]}: ${current_word}"
done

log "patching ${target_rel}"
for off in "${offsets[@]}"; do
    write_nop "${off}"
done

new_sha="$(sha256sum "${target}" | awk '{print $1}')"
[[ "${new_sha}" == "${expected_patched_sha}" ]] ||
    die "Patched storage.hdl sha256 mismatch: ${new_sha}"

log "patched ${target_rel} successfully"
