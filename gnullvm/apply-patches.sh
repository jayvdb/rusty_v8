#!/usr/bin/env bash
# Apply the MSYS2 mingw-w64-v8 patch set to rusty_v8's vendored Chromium sub-repos so V8 can be built with the
# llvm-mingw (x86_64-pc-windows-gnullvm) toolchain instead of clang-cl/MSVC.
#
# Patch -> sub-repo mapping mirrors the MSYS2 PKGBUILD prepare() step:
#   001        -> build/                 (chromium_build: defines the mingw gn toolchain + drops *.lib lib names)
#   015        -> third_party/abseil-cpp (build abseil as a static lib)
#   016        -> third_party/zlib       (system-zlib swap; only if rusty_v8 vendors zlib there)
#   002-014,017-> v8/                     (V8 source portability fixes for the GNU/Clang Windows build)
#
# Iteration aid: each patch is applied with --forward and a failure is recorded rather than fatal, so a single CI
# run surfaces every patch that needs rebasing against the pinned V8 revision instead of stopping at the first
# reject. The script exits non-zero only if a patch fails, after listing them all.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
patches="$here/patches"
failed=()

apply() {
  dir="$1"
  patch_file="$2"
  if [ ! -d "$dir" ]; then
    echo "[skip] $patch_file: target dir '$dir' absent in this checkout"
    return
  fi
  echo "[apply] $patch_file -> $dir/"
  if patch -d "$dir" -p1 --forward --no-backup-if-mismatch <"$patches/$patch_file"; then
    echo "[ok]    $patch_file"
  else
    echo "[FAIL]  $patch_file"
    failed+=("$patch_file")
  fi
}

apply build "001-add-mingw-toolchain.patch"
apply third_party/abseil-cpp "015-abseil-build-as-static-lib.patch"
apply third_party/zlib "016-zlib-use-system-lib.patch"

for p in \
  002-buildflags-fixes \
  003-fix-macros-and-functions \
  004-fix-static-assert-implementations \
  005-fix-conflicting-macros \
  006-support-clang-in-mingw-mode \
  007-snapshot-use-system-zlib-header \
  008-prioritized-native-thread-on-windows \
  009-unicode-for-wide-char-functions \
  010-disable-msvc-hack \
  011-make-sure-that-__rdtsc-is-declared \
  012-remove-dllimport-attributes \
  013-builtin-deps-fixes \
  014-heap-use-proper-sources \
  017-highway-disable-avx10-on-mingw; do
  apply v8 "$p.patch"
done

if [ "${#failed[@]}" -gt 0 ]; then
  echo "::warning::mingw patches needing a rebase against the pinned V8 revision: ${failed[*]}"
  exit 1
fi
echo "all mingw patches applied cleanly"
