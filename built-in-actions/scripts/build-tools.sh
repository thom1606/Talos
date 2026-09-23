#!/bin/bash
# Extension-owned codecs. No Homebrew libraries or runtime downloads in the shipped package.
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
configuration_hash="$(shasum -a 256 scripts/build-tools.sh | cut -d ' ' -f 1)"
jobs="$(sysctl -n hw.logicalcpu 2>/dev/null || printf 4)"
mkdir -p vendor/sources vendor/bin vendor/licenses vendor/build
fetch() {
  local name="$1" url="$2" checksum="$3"
  test -f "vendor/sources/$name" || curl --fail --location --proto '=https' --tlsv1.2 "$url" -o "vendor/sources/$name"
  printf '%s  %s\n' "$checksum" "vendor/sources/$name" | shasum -a 256 -c -
}
fetch ffmpeg-8.1.tar.xz https://ffmpeg.org/releases/ffmpeg-8.1.tar.xz b072aed6871998cce9b36e7774033105ca29e33632be5b6347f3206898e0756a
fetch libjpeg-turbo-3.1.3.tar.gz https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/3.1.3/libjpeg-turbo-3.1.3.tar.gz 075920b826834ac4ddf97661cc73491047855859affd671d52079c6867c1c6c0
# Retain the exact source archives alongside the binaries for LGPL redistribution.
test -d vendor/build/ffmpeg-8.1 || tar -xf vendor/sources/ffmpeg-8.1.tar.xz -C vendor/build
test -d vendor/build/libjpeg-turbo-3.1.3 || tar -xf vendor/sources/libjpeg-turbo-3.1.3.tar.gz -C vendor/build
cp vendor/build/ffmpeg-8.1/COPYING.LGPLv2.1 vendor/licenses/FFmpeg-LGPL-2.1.txt
cp vendor/build/libjpeg-turbo-3.1.3/LICENSE.md vendor/licenses/libjpeg-turbo.txt
cp vendor/build/libjpeg-turbo-3.1.3/README.ijg vendor/licenses/libjpeg-IJG.txt
for arch in ${ARCHS:-$(uname -m)}; do
  mkdir -p "vendor/build/ffmpeg-$arch" "vendor/build/jpeg-$arch" "vendor/bin/$arch"
  if [[ ! -f "vendor/bin/$arch/.configuration" ]] || [[ "$(cat "vendor/bin/$arch/.configuration")" != "$configuration_hash" ]]; then
    rm -f "vendor/bin/$arch/ffmpeg" "vendor/bin/$arch/ffprobe" "vendor/bin/$arch/jpegtran" "vendor/bin/$arch/cjpeg" "vendor/bin/$arch/djpeg"
  fi
  if [[ ! -x "vendor/bin/$arch/ffmpeg" ]]; then
    (
      cd "vendor/build/ffmpeg-$arch"
      ../ffmpeg-8.1/configure --sysroot="$(xcrun --sdk macosx --show-sdk-path)" --arch="$arch" --target-os=darwin --enable-cross-compile \
        --cc="$(xcrun -f clang) -arch $arch" --disable-autodetect --disable-network \
        --disable-gpl --disable-nonfree --disable-doc --disable-debug --disable-x86asm \
        --disable-shared --enable-static --disable-ffplay --enable-videotoolbox --enable-audiotoolbox --enable-zlib \
        --disable-encoders --enable-encoder=png,mjpeg,tiff,bmp,gif,h264_videotoolbox,hevc_videotoolbox,aac,alac,flac,pcm_s16le,pcm_s24le,pcm_s32le,pcm_f32le \
        --extra-cflags=-mmacosx-version-min=14.0 --extra-ldflags=-mmacosx-version-min=14.0
      make -j "$jobs"
      cp ffmpeg ffprobe "$root/vendor/bin/$arch/"
    )
  fi
  if [[ ! -x "vendor/bin/$arch/jpegtran" || ! -x "vendor/bin/$arch/cjpeg" || ! -x "vendor/bin/$arch/djpeg" ]]; then
    cmake -S vendor/build/libjpeg-turbo-3.1.3 -B "vendor/build/jpeg-$arch" \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES="$arch" -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
      -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_SIMD=OFF
    cmake --build "vendor/build/jpeg-$arch" --target jpegtran-static cjpeg-static djpeg-static -j "$jobs"
    cp "vendor/build/jpeg-$arch/jpegtran-static" "vendor/bin/$arch/jpegtran"
    cp "vendor/build/jpeg-$arch/cjpeg-static" "vendor/bin/$arch/cjpeg"
    cp "vendor/build/jpeg-$arch/djpeg-static" "vendor/bin/$arch/djpeg"
  fi
  printf '%s' "$configuration_hash" > "vendor/bin/$arch/.configuration"
  for tool in ffmpeg ffprobe jpegtran cjpeg djpeg; do
    # Only system frameworks/dylibs may be linked. Never depend on the build machine's Homebrew.
    if otool -L "vendor/bin/$arch/$tool" | tail -n +2 | awk '{print $1}' | grep -Ev '^(/usr/lib/|/System/Library/)' ; then
      echo "Unexpected non-system codec dependency" >&2; exit 1
    fi
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --options runtime "vendor/bin/$arch/$tool"
  done
done
