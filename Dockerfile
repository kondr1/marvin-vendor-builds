# Build container for Marvin vendor components.
#
# Approach: cross-compile for aarch64-musl without emulation.
#   - zig acts as the cross-compiler: it ships musl and compiler-rt with it,
#     so no external cross-toolchain has to be obtained or built;
#   - static libraries (OpenSSL, libnl) are not built by us, they are taken
#     prebuilt from the Alpine aarch64 repositories, already built against musl.
#
# The image is consumed BY DIGEST (see container.digest), not by tag: the exact
# set of package versions inside is pinned by the digest and nothing else.
FROM alpine:3.22

RUN apk add --no-cache \
	zig \
	bash make curl tar xz gnupg binutils file coreutils \
	pkgconf

# aarch64 sysroot: headers and static libraries only.
ARG ALPINE_BRANCH=v3.22
ARG SYSROOT=/sysroot
RUN apk add --no-cache --arch aarch64 --allow-untrusted \
	--root "$SYSROOT" --initdb \
	--repository "https://dl-cdn.alpinelinux.org/alpine/${ALPINE_BRANCH}/main" \
	musl-dev linux-headers \
	openssl-dev openssl-libs-static \
	libnl3-dev libnl3-static

ENV SYSROOT=/sysroot
WORKDIR /work
