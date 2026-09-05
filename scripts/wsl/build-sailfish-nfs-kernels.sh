#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 UPSTREAM_REPOSITORY OUTPUT_DIRECTORY BUILD_ID" >&2
  exit 2
fi

repo=$1
result_dir=$2
build_id=$3
log="$result_dir/build.log"

mkdir -p "$result_dir"
: >"$log"
exec > >(tee -a "$log") 2>&1

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nix-bin ca-certificates git xz-utils
export NIX_REMOTE=local
mkdir -p /nix/var/nix/profiles/per-user/root
nix-store --init

nix_flags=(--extra-experimental-features "nix-command flakes" --option sandbox false)
flake="path:$repo"

reference_store=$(nix "${nix_flags[@]}" build --no-link --print-out-paths \
  "$flake#marlin.\"$build_id\".kernels.stock")
nfs_store=$(nix "${nix_flags[@]}" build --no-link --print-out-paths \
  "$flake#marlin.\"$build_id\".kernels.specialNfs")

install -m 0644 "$reference_store/Image.lz4-dtb" "$result_dir/reference-Image.lz4-dtb"
install -m 0644 "$nfs_store/Image.lz4-dtb" "$result_dir/nfs-Image.lz4-dtb"
sha256sum "$result_dir/reference-Image.lz4-dtb" "$result_dir/nfs-Image.lz4-dtb" \
  | tee "$result_dir/SHA256SUMS"

printf 'build_id=%s\nreference_store=%s\nnfs_store=%s\n' \
  "$build_id" "$reference_store" "$nfs_store" >"$result_dir/build-metadata.txt"

echo "BUILD COMPLETE"
ls -lh "$result_dir"
