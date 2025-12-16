#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WCPP="${ROOT}/vendor/whisper.cpp"

IOS_MIN="${IOS_MIN:-14.0}"
MACOS_MIN="${MACOS_MIN:-13.0}"

OUT_DIR="${ROOT}/Frameworks"
BUILD_DIR="${ROOT}/build"
STAGE="${BUILD_DIR}/stage"
HEADERS="${STAGE}/headers"

die() { echo "❌ $*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }

preflight() {
  need_cmd cmake
  need_cmd xcrun
  need_cmd xcodebuild
  need_cmd libtool
  need_cmd lipo

  local dev_dir
  dev_dir="$(xcode-select -p 2>/dev/null || true)"
  [[ -n "${dev_dir}" ]] || die "xcode-select not configured. Install Xcode."
  [[ "${dev_dir}" != "/Library/Developer/CommandLineTools" ]] || die "Active developer dir is CommandLineTools. Switch to Xcode:
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"

  xcrun --sdk iphoneos --show-sdk-path >/dev/null
  xcrun --sdk iphonesimulator --show-sdk-path >/dev/null
  xcrun --sdk macosx --show-sdk-path >/dev/null
}

rm -rf "${BUILD_DIR}"
mkdir -p "${OUT_DIR}" "${STAGE}" "${HEADERS}"

preflight

cp -f "${WCPP}/include/whisper.h" "${HEADERS}/whisper.h"

cat > "${HEADERS}/module.modulemap" <<'MM'
module WhisperCpp [system] {
  header "whisper.h"
  export *
}
MM

# Build one arch for one SDK and merge all libs into one archive.
build_arch() {
  local plat="$1" sdk="$2" arch="$3" deploy="$4" sysname="$5"
  local bdir="${BUILD_DIR}/${plat}-${arch}"

  local sdk_path cc cxx
  sdk_path="$(xcrun --sdk "${sdk}" --show-sdk-path)"
  cc="$(xcrun --sdk "${sdk}" --find clang)"
  cxx="$(xcrun --sdk "${sdk}" --find clang++)"

  echo "==> Configuring ${plat} (${sdk}) ${arch} (min ${deploy})"
  cmake -S "${WCPP}" -B "${bdir}" -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME="${sysname}" \
    -DCMAKE_OSX_SYSROOT="${sdk_path}" \
    -DCMAKE_OSX_ARCHITECTURES="${arch}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${deploy}" \
    -DCMAKE_C_COMPILER="${cc}" \
    -DCMAKE_CXX_COMPILER="${cxx}" \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DBUILD_SHARED_LIBS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_SERVER=OFF \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON

  echo "==> Building ${plat} ${arch}"
  cmake --build "${bdir}" -j "$(sysctl -n hw.ncpu)"

  local whisper_a
  whisper_a="$(find "${bdir}" -maxdepth 6 -name "libwhisper*.a" | head -n 1 || true)"
  [[ -n "${whisper_a}" ]] || die "Could not find libwhisper*.a in ${bdir}"

  mkdir -p "${STAGE}/${plat}/${arch}"

  # Collect ggml libs into a temp file list (POSIX-safe)
  local ggml_list="${bdir}/ggml_libs.txt"
  find "${bdir}" -maxdepth 6 -name "libggml*.a" | sort > "${ggml_list}"
  [[ -s "${ggml_list}" ]] || die "Could not find any libggml*.a in ${bdir}"

  # Build libtool args safely
  # shellcheck disable=SC2046
  libtool -static -o "${STAGE}/${plat}/${arch}/libWhisperCpp.a" \
    "${whisper_a}" $(cat "${ggml_list}")

  echo "==> Built ${STAGE}/${plat}/${arch}/libWhisperCpp.a"
}

# 1) Build per-arch
build_arch "ios"    "iphoneos"        "arm64"   "${IOS_MIN}"   "iOS"
build_arch "iossim" "iphonesimulator" "arm64"   "${IOS_MIN}"   "iOS"
build_arch "iossim" "iphonesimulator" "x86_64"  "${IOS_MIN}"   "iOS"
build_arch "macos"  "macosx"          "arm64"   "${MACOS_MIN}" "Darwin"
build_arch "macos"  "macosx"          "x86_64"  "${MACOS_MIN}" "Darwin"

# 2) Lipo universal where needed
mkdir -p "${STAGE}/universal/ios" "${STAGE}/universal/iossim" "${STAGE}/universal/macos"

cp -f "${STAGE}/ios/arm64/libWhisperCpp.a" "${STAGE}/universal/ios/libWhisperCpp.a"

lipo -create \
  "${STAGE}/iossim/arm64/libWhisperCpp.a" \
  "${STAGE}/iossim/x86_64/libWhisperCpp.a" \
  -output "${STAGE}/universal/iossim/libWhisperCpp.a"

lipo -create \
  "${STAGE}/macos/arm64/libWhisperCpp.a" \
  "${STAGE}/macos/x86_64/libWhisperCpp.a" \
  -output "${STAGE}/universal/macos/libWhisperCpp.a"

echo "==> Lipo results:"
lipo -info "${STAGE}/universal/ios/libWhisperCpp.a"
lipo -info "${STAGE}/universal/iossim/libWhisperCpp.a"
lipo -info "${STAGE}/universal/macos/libWhisperCpp.a"

# 3) Create xcframework
rm -rf "${OUT_DIR}/WhisperCpp.xcframework"
xcodebuild -create-xcframework \
  -library "${STAGE}/universal/ios/libWhisperCpp.a" -headers "${HEADERS}" \
  -library "${STAGE}/universal/iossim/libWhisperCpp.a" -headers "${HEADERS}" \
  -library "${STAGE}/universal/macos/libWhisperCpp.a" -headers "${HEADERS}" \
  -output "${OUT_DIR}/WhisperCpp.xcframework"

echo "✅ Built ${OUT_DIR}/WhisperCpp.xcframework"