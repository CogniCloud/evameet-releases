#!/usr/bin/env bash
set -euo pipefail
# Ubuntu 24.04: sudo apt-get install gcc gcc-mingw-w64-x86-64-posix make nasm pkgconf xz-utils zip
# This script is distributed alongside the exact, unmodified upstream sources.
recipe_dir="$(cd "$(dirname "$0")" && pwd)"
out_dir="$(mkdir -p "${1:-out}" && cd "${1:-out}" && pwd)"
source_version=8.0.3
source_hash=6136812ea6d4e68bdba27e33c2a94382711cdf4f8602ffef056ff792bd6f9818
archive="ffmpeg-$source_version.tar.xz"
# EvaMeet films sittings with the H.264/HEVC encoders already on the post:
# Media Foundation ships with Windows, NVENC and AMF come with the NVIDIA and
# AMD drivers. FFmpeg loads all three at run time; only their headers are
# used here, MIT and header-only. Nothing is GPL, nonfree or version 3.
# The OLDEST headers FFmpeg 8.0 accepts are pinned on purpose: an older API
# runs on more of the drivers already installed in town halls.
nv_version=11.1.5.4
nv_hash=3651b887e2ada1d71b579b3dea22a7fda74e44919cf70dcff79b5b17fadc2078
nv_archive="nv-codec-headers-$nv_version.tar.gz"
amf_version=1.4.36
amf_hash=ec07ee21b820a73f5bae224e92fd3c492f52732d4885f0637f48189afdd87564
amf_archive="AMF-headers-v$amf_version.tar.gz"
video_encoders="h264_mf hevc_mf h264_nvenc hevc_nvenc h264_amf hevc_amf"

fetch() {
  if [[ ! -f "$2" ]]; then
    curl --fail --location --retry 3 "$1" -o "$2"
  fi
  echo "$3  $2" | sha256sum --check --strict
}

cd "$out_dir"
fetch "https://ffmpeg.org/releases/$archive" "$archive" "$source_hash"
fetch "https://github.com/FFmpeg/nv-codec-headers/releases/download/n$nv_version/$nv_archive" "$nv_archive" "$nv_hash"
fetch "https://github.com/GPUOpen-LibrariesAndSDKs/AMF/releases/download/v$amf_version/$amf_archive" "$amf_archive" "$amf_hash"

headers="$out_dir/headers"
rm -rf "$headers" "nv-codec-headers-$nv_version" "amf-headers-v$amf_version"
mkdir -p "$headers/include"
tar -xf "$nv_archive"
make -C "nv-codec-headers-$nv_version" PREFIX="$headers" install
tar -xf "$amf_archive"
cp -R "amf-headers-v$amf_version/AMF" "$headers/include/"

tar -xf "$archive"
cd "ffmpeg-$source_version"
# PKG_CONFIG_LIBDIR rather than _PATH: these headers only, never a .pc file
# of the build machine. D3D11VA is required by the Media Foundation encoder of
# FFmpeg 8.0 (mfenc.c declares D3D11 types but includes their header only
# when D3D11VA is enabled); d3d11.dll and dxgi.dll are loaded at run time.
PKG_CONFIG_LIBDIR="$headers/lib/pkgconfig" ./configure \
  --target-os=mingw32 --arch=x86_64 --enable-cross-compile \
  --cross-prefix=x86_64-w64-mingw32- --cc=x86_64-w64-mingw32-gcc-posix \
  --pkg-config=pkg-config --extra-cflags="-I$headers/include" \
  --disable-autodetect --disable-gpl --disable-nonfree --disable-version3 \
  --enable-mediafoundation --enable-d3d11va --enable-ffnvcodec --enable-nvenc --enable-amf \
  --disable-network --disable-doc --disable-debug --disable-ffplay --disable-ffprobe \
  --disable-shared --enable-static --extra-ldflags=-static
# configure drops what it cannot build. A binary that would film nothing, or
# could not open a camera, is refused here rather than on a council night.
for encoder in $video_encoders; do
  if ! grep -qx "CONFIG_${encoder^^}_ENCODER=yes" ffbuild/config.mak; then
    echo "Video encoder missing from the build: $encoder" >&2
    exit 1
  fi
done
if ! grep -qx 'CONFIG_DSHOW_INDEV=yes' ffbuild/config.mak; then
  echo 'DirectShow camera capture missing from the build' >&2
  exit 1
fi
make -j"$(nproc)" ffmpeg.exe

package_name="ffmpeg-$source_version-evameet-win64"
package_dir="$out_dir/$package_name"
source_dir="$out_dir/ffmpeg-$source_version-evameet-source"
mkdir -p "$package_dir/bin" "$package_dir/licenses" "$source_dir/build-configuration"
cp ffmpeg.exe "$package_dir/bin/"
cp COPYING.LGPLv2.1 LICENSE.md "$package_dir/licenses/"
cp ffbuild/config.mak config.h config_components.h "$source_dir/build-configuration/"
cp "$out_dir/$archive" "$out_dir/$nv_archive" "$out_dir/$amf_archive" "$source_dir/"
cp "$recipe_dir/build-windows.sh" "$source_dir/"
cp COPYING.LGPLv2.1 LICENSE.md "$source_dir/"
# The MIT notices travel with the binary. Each header carries its own.
{
  echo "nv-codec-headers $nv_version, https://github.com/FFmpeg/nv-codec-headers (MIT)."
  echo "Notice of each header compiled into ffmpeg.exe:"
  for header in "$out_dir/nv-codec-headers-$nv_version"/include/ffnvcodec/*.h; do
    printf '\n== %s\n' "${header##*/}"
    sed -n '1,/\*\//p' "$header"
  done
} > "$package_dir/licenses/nv-codec-headers-LICENSE.txt"
{
  echo "AMF headers $amf_version, https://github.com/GPUOpen-LibrariesAndSDKs/AMF (MIT)."
  echo "Every AMF header carries this notice:"
  echo
  awk '/^\/\//{print; next} {exit}' "$out_dir/amf-headers-v$amf_version/AMF/core/Version.h"
} > "$package_dir/licenses/AMF-LICENSE.txt"
cp "$package_dir/licenses/nv-codec-headers-LICENSE.txt" "$package_dir/licenses/AMF-LICENSE.txt" "$source_dir/"
printf '%s\n' 'Unmodified upstream sources. Extract the tarballs; build-windows.sh verifies their SHA-256 before building. The configure command is in build-windows.sh. EvaMeet starts this executable as a separate process and does not link these libraries into EvaMeet. Media Foundation, NVENC and AMF are loaded at run time from Windows and from the GPU driver; only their MIT headers are used here.' > "$source_dir/README.txt"
printf '%s\n' "$source_hash  $archive" "$nv_hash  $nv_archive" "$amf_hash  $amf_archive" > "$source_dir/SOURCE-SHA256.txt"
: > "$source_dir/changes.diff"
x86_64-w64-mingw32-gcc-posix --version > "$source_dir/build-configuration/compiler.txt"
dpkg-query -W gcc gcc-mingw-w64-x86-64-posix mingw-w64-common binutils-mingw-w64-x86-64 nasm make pkgconf > "$source_dir/build-configuration/toolchain-packages.txt"
cp /usr/share/doc/mingw-w64-common/copyright "$source_dir/MinGW-copyright.txt"
cp /usr/share/doc/gcc-mingw-w64-x86-64-posix/copyright "$source_dir/GCC-copyright.txt"
cp "$source_dir/MinGW-copyright.txt" "$source_dir/GCC-copyright.txt" "$package_dir/licenses/"
x86_64-w64-mingw32-objdump -p ffmpeg.exe > "$source_dir/build-configuration/pe-imports.txt"
if grep -Ei 'DLL Name:.*(libgcc|libwinpthread|libstdc)' "$source_dir/build-configuration/pe-imports.txt"; then
  echo 'Unexpected external compiler runtime DLL' >&2
  exit 1
fi
# FFmpeg must still start, and record the audio, on a post without Media
# Foundation (Windows N, Windows Server) or without a GPU driver. These DLLs
# may only be loaded at run time, never imported at load time.
if grep -Ei 'DLL Name: *(mfplat|mf|mfreadwrite|evr|d3d11|dxgi|d3d9|dxva2|nvcuda|nvencodeapi64|amfrt64)\.dll' "$source_dir/build-configuration/pe-imports.txt"; then
  echo 'An optional Windows or GPU driver DLL is imported at load time' >&2
  exit 1
fi
cd "$out_dir"
zip -qr "$package_name.zip" "$package_name"
tar -cJf "ffmpeg-$source_version-evameet-source.tar.xz" "ffmpeg-$source_version-evameet-source"
sha256sum "$package_name.zip" "ffmpeg-$source_version-evameet-source.tar.xz" "$package_name/bin/ffmpeg.exe" > SHA256SUMS.txt
