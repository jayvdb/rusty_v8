#!/usr/bin/env bash
# Apply the mingw porting patches to rusty_v8's vendored Chromium sub-repos so V8 builds with the llvm-mingw
# (x86_64-pc-windows-gnullvm) toolchain instead of clang-cl/MSVC.
#
# Patches are rebased from the MSYS2 mingw-w64-v8 recipe onto denoland's forks:
#   001 -> build/   regenerated against denoland's chromium_build, which ALREADY wires is_mingw/is_msvc in
#                   BUILDCONFIG.gn and selects //build/toolchain/win:mingw_$target_cpu -- 001 now supplies only the
#                   missing mingw_toolchain definition + the compiler/win/toolchain config it needs.
#   002-014,017 -> v8/   V8 source portability fixes (denoland's v8 fork has no mingw support).
#
# MSYS2 patches 007 (system-zlib header), 015 (abseil-as-static-lib) and 016 (system zlib) are intentionally NOT
# applied: they target MSYS2's system-library build model, whereas rusty_v8 builds zlib/abseil from its own
# vendored submodules. Add them back only if gn gen / the compile shows they are needed.
#
# Each patch is applied with --forward; a failure is recorded (not fatal) so one CI run surfaces every patch that
# needs a rebase rather than stopping at the first reject. Exits non-zero if any patch failed.
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

for p in \
  002-buildflags-fixes \
  003-fix-macros-and-functions \
  004-fix-static-assert-implementations \
  005-fix-conflicting-macros \
  006-support-clang-in-mingw-mode \
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
  echo "::warning::mingw patches needing a rebase against the pinned revisions: ${failed[*]}"
  exit 1
fi
echo "all mingw patches applied cleanly"
