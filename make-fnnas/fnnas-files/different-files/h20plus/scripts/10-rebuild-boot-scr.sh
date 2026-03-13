#!/bin/bash
set -euo pipefail

script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
board_dir="$(cd -- "${script_dir}/.." && pwd)"
bootfs_dir="${FNNAS_BOARD_BOOTFS_DIR:-${board_dir}/bootfs}"
boot_cmd="${bootfs_dir}/boot.cmd"
boot_scr="${bootfs_dir}/boot.scr"
mkimage_cache_dir="${board_dir}/.cache/mkimage"
uboot_release_repo="${FNNAS_UBOOT_RELEASE_REPO:-cccsaber/u-boot}"
uboot_release_download="https://github.com/${uboot_release_repo}/releases/download"
mkimage_asset_name="${FNNAS_UBOOT_MKIMAGE_ASSET:-mkimage}"
release_tag="${FNNAS_UBOOT_RELEASE_TAG:-uboot_h20plus}"
release_url="${uboot_release_download}/${release_tag}/${mkimage_asset_name}"
mkimage_bin="${mkimage_cache_dir}/${release_tag}/${mkimage_asset_name}"
mkimage_tmp="${mkimage_bin}.tmp.$$"
image_name="${FNNAS_BOOTSCR_NAME:-flatmax load script}"

log() {
    printf '[h20plus] %s\n' "$*"
}

die() {
    printf '[h20plus] ERROR: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    rm -f "${mkimage_tmp}"
}
trap cleanup EXIT

[[ -f "${boot_cmd}" ]] || die "Missing ${boot_cmd}"
log "bootfs dir ${bootfs_dir}"
log "boot.cmd sha256 $(sha256sum "${boot_cmd}" | awk '{print $1}')"
[[ "$(uname -m)" =~ ^(x86_64|amd64)$ ]] || die "Remote ${mkimage_asset_name} only supports x86_64 hosts"

mkdir -p "$(dirname "${mkimage_bin}")"

if [[ -x "${mkimage_bin}" ]]; then
    if "${mkimage_bin}" -V >/dev/null 2>&1; then
        log "using cached mkimage ${mkimage_bin}"
    else
        rm -f "${mkimage_bin}"
    fi
fi

if [[ ! -x "${mkimage_bin}" ]]; then
    log "downloading ${mkimage_asset_name} from ${release_url}"
    for t in {1..10}; do
        curl -fsSL "${release_url}" -o "${mkimage_tmp}"
        [[ "${?}" -eq 0 ]] && break || sleep 60
    done
    [[ "${?}" -eq 0 ]] || die "Failed to download ${mkimage_asset_name} from ${release_url}"
    chmod 755 "${mkimage_tmp}" || die "Failed to chmod ${mkimage_tmp}"
    "${mkimage_tmp}" -V >/dev/null 2>&1 || die "Downloaded ${mkimage_asset_name} is not executable on this host"
    mv -f "${mkimage_tmp}" "${mkimage_bin}" || die "Failed to cache ${mkimage_asset_name}"
fi

rm -f "${boot_scr}"
log "rebuilding ${boot_scr} from ${boot_cmd}"
"${mkimage_bin}" -C none -A arm -T script -n "${image_name}" -d "${boot_cmd}" "${boot_scr}" >/dev/null 2>&1 ||
    die "Failed to rebuild ${boot_scr}"

"${mkimage_bin}" -l "${boot_scr}" >/dev/null 2>&1 || die "Generated ${boot_scr} failed mkimage header validation"
log "boot.scr sha256 $(sha256sum "${boot_scr}" | awk '{print $1}')"
log "rebuilt ${boot_scr} successfully"
