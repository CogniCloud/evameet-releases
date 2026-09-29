#!/usr/bin/env bash
set -euo pipefail
# Ubuntu 24.04: sudo apt-get install gcc-mingw-w64-x86-64-posix make nasm xz-utils zip
# This script is distributed alongside the exact, unmodified upstream sources.
recipe_dir="$(cd "$(dirname "$0")" && pwd)"
out_dir="$(mkdir -p "${1:-out}" && cd "${1:-out}" && pwd)"
source_version=8.0.3
source_hash=6136812ea6d4e68bdba27e33c2a94382711cdf4f8602ffef056ff792bd6f9818
archive="ffmpeg-$source_version.tar.xz"
cd "$out_dir"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 "https://ffmpeg.org/releases/$archive" -o "$archive"
fi
echo "$source_hash  $archive" | sha256sum --check --strict
tar -xf "$archive"
cd "ffmpeg-$source_version"
./configure \
  --target-os=mingw32 --arch=x86_64 --enable-cross-compile \
  --cross-prefix=x86_64-w64-mingw32- --cc=x86_64-w64-mingw32-gcc-posix \
  --disable-autodetect --disable-gpl --disable-nonfree --disable-version3 \
  --disable-network --disable-doc --disable-debug --disable-ffplay --disable-ffprobe \
  --disable-shared --enable-static --extra-ldflags=-static
make -j"$(nproc)" ffmpeg.exe

package_name="ffmpeg-$source_version-evameet-win64"
package_dir="$out_dir/$package_name"
source_dir="$out_dir/ffmpeg-$source_version-evameet-source"
mkdir -p "$package_dir/bin" "$package_dir/licenses" "$source_dir/build-configuration"
cp ffmpeg.exe "$package_dir/bin/"
cp COPYING.LGPLv2.1 LICENSE.md "$package_dir/licenses/"
cp ffbuild/config.mak config.h config_components.h "$source_dir/build-configuration/"
cp "$out_dir/$archive" "$source_dir/"
cp "$recipe_dir/build-windows.sh" "$source_dir/"
cp COPYING.LGPLv2.1 LICENSE.md "$source_dir/"
printf '%s\n' 'Unmodified upstream source. Extract the tarball; build-windows.sh verifies its SHA-256 before building. The configure command is in build-windows.sh. EvaMeet starts this executable as a separate process and does not link these libraries into EvaMeet.' > "$source_dir/README.txt"
printf '%s\n' "$source_hash  $archive" > "$source_dir/SOURCE-SHA256.txt"
: > "$source_dir/changes.diff"
x86_64-w64-mingw32-gcc-posix --version > "$source_dir/build-configuration/compiler.txt"
dpkg-query -W gcc-mingw-w64-x86-64-posix mingw-w64-common binutils-mingw-w64-x86-64 nasm make > "$source_dir/build-configuration/toolchain-packages.txt"
cp /usr/share/doc/mingw-w64-common/copyright "$source_dir/MinGW-copyright.txt"
cp /usr/share/doc/gcc-mingw-w64-x86-64-posix/copyright "$source_dir/GCC-copyright.txt"
cp "$source_dir/MinGW-copyright.txt" "$source_dir/GCC-copyright.txt" "$package_dir/licenses/"
x86_64-w64-mingw32-objdump -p ffmpeg.exe > "$source_dir/build-configuration/pe-imports.txt"
if grep -Ei 'DLL Name:.*(libgcc|libwinpthread|libstdc)' "$source_dir/build-configuration/pe-imports.txt"; then
  echo 'Unexpected external compiler runtime DLL' >&2
  exit 1
fi
cd "$out_dir"
zip -qr "$package_name.zip" "$package_name"
tar -cJf "ffmpeg-$source_version-evameet-source.tar.xz" "ffmpeg-$source_version-evameet-source"
sha256sum "$package_name.zip" "ffmpeg-$source_version-evameet-source.tar.xz" "$package_name/bin/ffmpeg.exe" > SHA256SUMS.txt
