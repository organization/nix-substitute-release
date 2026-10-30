#!/usr/bin/env bash
set -euo pipefail

# Prepare
directory=$(realpath -m -- "$NSR_CACHE_DIRECTORY")
store_path=$(readlink -f -- "$NSR_STORE_PATH")
store_name=$(basename -- "$store_path")
store_hash=${store_name%%-*}
key_name=${NSR_PUBLIC_KEY%%:*}
signing_key=$(mktemp)
trap 'rm -f "$signing_key"' EXIT
chmod 600 "$signing_key"
printf '%s\n' "$NSR_PRIVATE_KEY" > "$signing_key"
mkdir -p -- "$directory"

# Sign
nix store sign --key-file "$signing_key" "$store_path"
nix store verify --sigs-needed 1 --option trusted-public-keys "$NSR_PUBLIC_KEY" "$store_path"

# Archive
archive_path="$directory/$store_hash.nar.zst"
nix store dump-path "$store_path" | zstd -T0 -q > "$archive_path"

# Write info
path_info=$(nix path-info --json --sigs "$store_path")
nar_hash=$(nix hash convert --to nix32 "$(jq -r '.[] | .narHash' <<< "$path_info")")
file_hash=$(nix hash file --type sha256 --base32 "$archive_path")
file_size=$(stat -c %s "$archive_path")

jq -r \
  --arg path "$store_path" \
  --arg hash "$store_hash" \
  --arg narHash "$nar_hash" \
  --arg fileHash "$file_hash" \
  --arg size "$file_size" \
  --arg keyName "$key_name" \
  '.[] |
    "StorePath: \($path)",
    "URL: \($hash).nar.zst",
    "Compression: zstd",
    "FileHash: sha256:\($fileHash)",
    "FileSize: \($size)",
    "NarHash: sha256:\($narHash)",
    "NarSize: \(.narSize)",
    "References: \(.references | map(split("/")[-1]) | sort | join(" "))",
    (.signatures[]? | select(startswith($keyName + ":")) | "Sig: \(.)")
  ' <<< "$path_info" > "$directory/$store_hash.narinfo"

printf '%s\n' \
  "StoreDir: $(dirname -- "$store_path")" \
  'WantMassQuery: 1' \
  'Priority: 50' > "$directory/nix-cache-info"

printf 'cache-directory=%s\nstore-path=%s\n' "$directory" "$store_path" >> "$GITHUB_OUTPUT"
