# Контейнер сборки vendor-компонентов Marvin.
#
# Подход: кросс-компиляция под aarch64-musl без эмуляции.
#   - zig выступает кросс-компилятором: несёт с собой musl и compiler-rt,
#     поэтому не нужен внешний cross-toolchain и его сборка;
#   - статические библиотеки (OpenSSL, libnl) не собираются нами, а берутся
#     готовыми из aarch64-репозиториев Alpine — они уже собраны под musl.
#
# Образ потребляется ПО DIGEST (см. container.digest), а не по тегу: точный
# набор версий пакетов внутри фиксируется именно digest'ом.
FROM alpine:3.22

RUN apk add --no-cache \
	zig \
	bash make curl tar xz gnupg binutils file coreutils \
	pkgconf

# Sysroot aarch64: только заголовки и статические библиотеки.
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
