#!/usr/bin/env bash
# Cross-build hostapd for aarch64-musl, statically linked.
#
# Runs IDENTICALLY locally and in CI, always inside the build container:
#   docker run --rm -v "$PWD:/work" <image-by-digest> scripts/build-hostapd.sh
#
# What it does: downloads the pinned sources, verifies the upstream signature
# and our own checksum, builds the static binary, checks the result and writes
# build-info.yaml for the consumer (see component-bundle.md §2).
set -euo pipefail

VERSION=${HOSTAPD_VERSION:-2.11}
SYSROOT=${SYSROOT:-/sysroot}
TARGET=${TARGET:-aarch64-linux-musl}
ARCH=${ARCH:-aarch64}

root=$(cd "$(dirname "$0")/.." && pwd)
downloads="$root/downloads"
src="$root/src/hostapd-$VERSION"
out="$root/out"
tarball="$downloads/hostapd-$VERSION.tar.gz"
base_url="https://w1.fi/releases"

mkdir -p "$downloads" "$out" "$root/src"

step() { printf '\n== %s\n' "$1"; }

# --- 1. Sources --------------------------------------------------------------
# Download cache: the tarball is immutable, so it is never fetched twice.
step "hostapd $VERSION sources"
if [ ! -f "$tarball" ]; then
	curl -fsSL -o "$tarball" "$base_url/hostapd-$VERSION.tar.gz"
	curl -fsSL -o "$tarball.asc" "$base_url/hostapd-$VERSION.tar.gz.asc"
fi

# --- 2. Verification ---------------------------------------------------------
# w1.fi publishes PGP signatures rather than checksum files, so the chain has
# two stages: upstream signature -> our own SHA256.
step "Authenticity check"
fingerprint_file="$root/hostapd/upstream-key.fingerprint"
if [ -f "$fingerprint_file" ] && [ -f "$tarball.asc" ]; then
	fpr=$(tr -d ' \n' < "$fingerprint_file")
	gpg --batch --quiet --recv-keys "$fpr" 2>/dev/null ||
		echo "WARNING: key $fpr not received, signature not verified"
	if gpg --batch --status-fd 1 --verify "$tarball.asc" "$tarball" 2>/dev/null |
		grep -q "VALIDSIG $fpr"; then
		echo "upstream signature: ok"
	else
		echo "ERROR: upstream signature not confirmed" >&2
		exit 1
	fi
else
	# TODO(build): pin the upstream key fingerprint and drop this branch.
	echo "WARNING: key fingerprint not pinned, signature check skipped"
fi

sha256=$(sha256sum "$tarball" | cut -d' ' -f1)
expected_file="$root/hostapd/hostapd-$VERSION.sha256"
if [ -f "$expected_file" ]; then
	expected=$(cut -d' ' -f1 < "$expected_file")
	[ "$sha256" = "$expected" ] || {
		echo "ERROR: SHA256 mismatch" >&2
		echo "  got:      $sha256" >&2
		echo "  expected: $expected" >&2
		exit 1
	}
	echo "SHA256: ok"
else
	echo "$sha256  hostapd-$VERSION.tar.gz" > "$expected_file"
	echo "SHA256 pinned for the first time: $sha256"
fi

# --- 3. Unpack and configure -------------------------------------------------
step "Configuration"
rm -rf "$src"
tar -xf "$tarball" -C "$root/src"

cp "$root/hostapd/hostapd.config" "$src/hostapd/.config"

# --- 4. Build ----------------------------------------------------------------
# The static archives are given as full paths: the sysroot also contains the
# matching .so files, and with -l the linker would pick the dynamic variant.
step "Building for $TARGET"
libs="$SYSROOT/usr/lib/libnl-genl-3.a $SYSROOT/usr/lib/libnl-3.a"
libs="$libs $SYSROOT/usr/lib/libssl.a $SYSROOT/usr/lib/libcrypto.a"

# pkg-config must answer for the sysroot, not for the host.
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

# Flags are passed via EXTRA_CFLAGS: overriding CFLAGS wipes out hostapd's own
# include paths (-I../src and friends) and the build falls apart.
make -C "$src/hostapd" hostapd \
	CC="zig cc -target $TARGET" \
	EXTRA_CFLAGS="-Os -I$SYSROOT/usr/include -I$SYSROOT/usr/include/libnl3" \
	LDFLAGS="-static -Wl,-s" \
	LIBS="$libs" \
	-j"$(nproc)"

# Symbols are stripped by the linker (-Wl,-s): the host binutils strip is built
# for x86 and does not handle a foreign architecture, while leaving the symbols
# in yields ~20 MB instead of a few — that is space in the image and in every
# OTA update.
cp "$src/hostapd/hostapd" "$out/hostapd"

"$root/scripts/verify-artifact.sh" "$out/hostapd" "$ARCH"
sha_out=$(sha256sum "$out/hostapd" | cut -d' ' -f1)

# --- 5. build-info.yaml ------------------------------------------------------
# Without it the consumer cannot prove what the binary was built from.
step "build-info.yaml"
cat > "$out/build-info.yaml" <<EOF
component: hostapd
version: "$VERSION"
target: $TARGET
arch: $ARCH
source_url: $base_url/hostapd-$VERSION.tar.gz
source_sha256: $sha256
artifact_sha256: $sha_out
build_container_digest: ${BUILD_CONTAINER_DIGEST:-unknown}
zig_version: $(zig version)
config: hostapd/hostapd.config
EOF

echo "$sha_out  hostapd" > "$out/hostapd.sha256"
cat "$out/build-info.yaml"
