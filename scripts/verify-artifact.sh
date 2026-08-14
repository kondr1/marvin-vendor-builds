#!/usr/bin/env sh
# Проверка собранного бинарника перед публикацией.
#
# Артефакт обязан быть статическим и под целевой архитектурой: на gokrazy нет
# C-runtime и динамического загрузчика, поэтому динамически слинкованный
# бинарник там просто не запустится.
#
# Использование: verify-artifact.sh <файл> <ожидаемая-архитектура>
#   verify-artifact.sh out/hostapd aarch64
set -eu

file_path=${1:?нужен путь к артефакту}
want_arch=${2:?нужна ожидаемая архитектура, напр. aarch64}

fail() {
	echo "ОШИБКА: $1" >&2
	exit 1
}

[ -f "$file_path" ] || fail "файл не найден: $file_path"

header=$(readelf -h "$file_path" 2>/dev/null) || fail "не ELF: $file_path"

case "$header" in
*"AArch64"*) got_arch=aarch64 ;;
*"X86-64"*) got_arch=x86_64 ;;
*"ARM"*) got_arch=arm ;;
*) got_arch=unknown ;;
esac

[ "$got_arch" = "$want_arch" ] ||
	fail "архитектура $got_arch, ожидалась $want_arch"

# Наличие PT_INTERP означает динамический загрузчик — на gokrazy его нет.
if readelf -l "$file_path" 2>/dev/null | grep -q "INTERP"; then
	fail "бинарник требует динамический загрузчик (PT_INTERP)"
fi

# NEEDED-записи означают зависимость от shared-библиотек.
if readelf -d "$file_path" 2>/dev/null | grep -q "(NEEDED)"; then
	fail "бинарник зависит от shared-библиотек"
fi

size=$(wc -c < "$file_path")
[ "$size" -gt 100000 ] || fail "подозрительно маленький артефакт: $size байт"

echo "ok: $file_path — статический $got_arch, $size байт"
