#!/usr/bin/env sh
# Check a built binary before publishing it.
#
# The artifact must be static and built for the target architecture: gokrazy has
# no C runtime and no dynamic loader, so a dynamically linked binary simply will
# not start there.
#
# Usage: verify-artifact.sh <file> <expected-arch>
#   verify-artifact.sh out/hostapd aarch64
set -eu

file_path=${1:?artifact path required}
want_arch=${2:?expected architecture required, e.g. aarch64}

fail() {
	echo "ERROR: $1" >&2
	exit 1
}

[ -f "$file_path" ] || fail "file not found: $file_path"

header=$(readelf -h "$file_path" 2>/dev/null) || fail "not an ELF: $file_path"

case "$header" in
*"AArch64"*) got_arch=aarch64 ;;
*"X86-64"*) got_arch=x86_64 ;;
*"ARM"*) got_arch=arm ;;
*) got_arch=unknown ;;
esac

[ "$got_arch" = "$want_arch" ] ||
	fail "architecture is $got_arch, expected $want_arch"

# A PT_INTERP entry means a dynamic loader is required — gokrazy has none.
if readelf -l "$file_path" 2>/dev/null | grep -q "INTERP"; then
	fail "binary requires a dynamic loader (PT_INTERP)"
fi

# NEEDED entries mean the binary depends on shared libraries.
if readelf -d "$file_path" 2>/dev/null | grep -q "(NEEDED)"; then
	fail "binary depends on shared libraries"
fi

size=$(wc -c < "$file_path")
[ "$size" -gt 100000 ] || fail "suspiciously small artifact: $size bytes"

echo "ok: $file_path — static $got_arch, $size bytes"
