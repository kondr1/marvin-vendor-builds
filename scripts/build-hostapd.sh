#!/usr/bin/env bash
# Кросс-сборка hostapd под aarch64-musl, статически.
#
# Запускается ОДИНАКОВО локально и в CI, всегда внутри контейнера сборки:
#   docker run --rm -v "$PWD:/work" <образ-по-digest> scripts/build-hostapd.sh
#
# Что делает: скачивает пиннутые исходники, проверяет подпись upstream и нашу
# контрольную сумму, собирает статический бинарник, проверяет результат и
# пишет build-info.yaml для потребителя (см. component-bundle.md §2).
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

# --- 1. Исходники ------------------------------------------------------------
# Кеш загрузок: тарболл неизменяем, повторно не качаем.
step "Исходники hostapd $VERSION"
if [ ! -f "$tarball" ]; then
	curl -fsSL -o "$tarball" "$base_url/hostapd-$VERSION.tar.gz"
	curl -fsSL -o "$tarball.asc" "$base_url/hostapd-$VERSION.tar.gz.asc"
fi

# --- 2. Проверки -------------------------------------------------------------
# w1.fi публикует PGP-подписи, а не файлы контрольных сумм, поэтому цепочка
# двухступенчатая: подпись upstream → наша SHA256.
step "Проверка подлинности"
fingerprint_file="$root/hostapd/upstream-key.fingerprint"
if [ -f "$fingerprint_file" ] && [ -f "$tarball.asc" ]; then
	fpr=$(tr -d ' \n' < "$fingerprint_file")
	gpg --batch --quiet --recv-keys "$fpr" 2>/dev/null ||
		echo "ВНИМАНИЕ: ключ $fpr не получен, подпись не проверена"
	if gpg --batch --status-fd 1 --verify "$tarball.asc" "$tarball" 2>/dev/null |
		grep -q "VALIDSIG $fpr"; then
		echo "подпись upstream: ok"
	else
		echo "ОШИБКА: подпись upstream не подтверждена" >&2
		exit 1
	fi
else
	# TODO(build): зафиксировать отпечаток ключа upstream и снять эту ветку.
	echo "ВНИМАНИЕ: отпечаток ключа не зафиксирован, проверка подписи пропущена"
fi

sha256=$(sha256sum "$tarball" | cut -d' ' -f1)
expected_file="$root/hostapd/hostapd-$VERSION.sha256"
if [ -f "$expected_file" ]; then
	expected=$(cut -d' ' -f1 < "$expected_file")
	[ "$sha256" = "$expected" ] || {
		echo "ОШИБКА: SHA256 не совпал" >&2
		echo "  получено:  $sha256" >&2
		echo "  ожидалось: $expected" >&2
		exit 1
	}
	echo "SHA256: ok"
else
	echo "$sha256  hostapd-$VERSION.tar.gz" > "$expected_file"
	echo "SHA256 зафиксирован впервые: $sha256"
fi

# --- 3. Распаковка и конфигурация --------------------------------------------
step "Конфигурация"
rm -rf "$src"
tar -xf "$tarball" -C "$root/src"

cp "$root/hostapd/hostapd.config" "$src/hostapd/.config"

# --- 4. Сборка ---------------------------------------------------------------
# Статические архивы указываются полными путями: в sysroot лежат и .so,
# по -l линковщик предпочтёт динамический вариант.
step "Сборка под $TARGET"
libs="$SYSROOT/usr/lib/libnl-genl-3.a $SYSROOT/usr/lib/libnl-3.a"
libs="$libs $SYSROOT/usr/lib/libssl.a $SYSROOT/usr/lib/libcrypto.a"

# pkg-config должен отвечать про sysroot, а не про хост.
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

# Флаги добавляются через EXTRA_CFLAGS: переопределение CFLAGS затирает
# собственные include-пути hostapd (-I../src и прочие) и сборка разваливается.
make -C "$src/hostapd" hostapd \
	CC="zig cc -target $TARGET" \
	EXTRA_CFLAGS="-Os -I$SYSROOT/usr/include -I$SYSROOT/usr/include/libnl3" \
	LDFLAGS="-static -Wl,-s" \
	LIBS="$libs" \
	-j"$(nproc)"

# Символы убирает линковщик (-Wl,-s): strip из binutils хоста собран под x86 и
# чужую архитектуру не обрабатывает, а неснятые символы дают ~20 МБ вместо
# нескольких — это место в образе и в каждом OTA-обновлении.
cp "$src/hostapd/hostapd" "$out/hostapd"

"$root/scripts/verify-artifact.sh" "$out/hostapd" "$ARCH"
sha_out=$(sha256sum "$out/hostapd" | cut -d' ' -f1)

# --- 5. build-info.yaml ------------------------------------------------------
# Без него потребитель не может доказать, из чего собран бинарник.
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
