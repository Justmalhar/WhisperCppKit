#!/usr/bin/env bash
set -euo pipefail

# ---- config you might change ----
REPO_NAME="${REPO_NAME:-WhisperCppKit}"
WHISPERCPP_REMOTE="${WHISPERCPP_REMOTE:-https://github.com/ggml-org/whisper.cpp.git}"
# Pin to a tag/commit if you want reproducibility. Leave as "master" or "main" to track upstream.
WHISPERCPP_REF="${WHISPERCPP_REF:-v1.8.2}"
IOS_MIN="${IOS_MIN:-14.0}"
MACOS_MIN="${MACOS_MIN:-13.0}"
# --------------------------------

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }; }
need git
need xcodebuild
need cmake
need libtool

mkdir -p Scripts Sources/WhisperSwift include Frameworks vendor .github/workflows

# Initialize git if needed
if [ ! -d .git ]; then
  git init
fi

# Add whisper.cpp as a submodule
if [ ! -d "vendor/whisper.cpp" ]; then
  git submodule add "${WHISPERCPP_REMOTE}" vendor/whisper.cpp
fi

# Checkout/pin whisper.cpp
pushd vendor/whisper.cpp >/dev/null
git fetch --tags --quiet || true
# Try tag first; fallback to branch name
git checkout -q "${WHISPERCPP_REF}" 2>/dev/null || git checkout -q "${WHISPERCPP_REF}" || true
popd >/dev/null

# .gitignore
cat > .gitignore <<'EOF'
.DS_Store
build/
DerivedData/
*.xcuserstate
Frameworks/*.xcframework/
Frameworks/*.zip
EOF

# Minimal Swift wrapper (you’ll extend later)
cat > Sources/WhisperSwift/WhisperSwift.swift <<'EOF'
import Foundation
import WhisperCpp

public enum WhisperSwiftError: Error {
    case invalidUTF8
}

public final class Whisper {
    public init() {}

    // Placeholder: you’ll wrap whisper_init_from_file / whisper_full, etc.
    public func hello() -> String {
        // sanity check the module imports + links
        return "WhisperCpp linked ✅"
    }
}
EOF

# SwiftPM manifest: local XCFramework binary target
cat > Package.swift <<EOF
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "${REPO_NAME}",
    platforms: [
        .iOS(.v${IOS_MIN%.*}),
        .macOS(.v${MACOS_MIN%.*})
    ],
    products: [
        .library(name: "WhisperSwift", targets: ["WhisperSwift"])
    ],
    targets: [
        .binaryTarget(
            name: "WhisperCpp",
            path: "Frameworks/WhisperCpp.xcframework"
        ),
        .target(
            name: "WhisperSwift",
            dependencies: ["WhisperCpp"],
            path: "Sources/WhisperSwift"
        )
    ]
)
EOF

# Build script to generate Frameworks/WhisperCpp.xcframework from vendor/whisper.cpp
cat > Scripts/build_xcframework.sh <<'EOF'
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

rm -rf "${BUILD_DIR}"
mkdir -p "${OUT_DIR}" "${STAGE}" "${HEADERS}"

# Copy headers we expose via modulemap
# whisper.h lives in whisper.cpp/include
cp -f "${WCPP}/include/whisper.h" "${HEADERS}/whisper.h"

# Add a module map so Swift can import it as `import WhisperCpp`
cat > "${HEADERS}/module.modulemap" <<'MM'
module WhisperCpp [system] {
  header "whisper.h"
  export *
}
MM

# Helper: build static libs for a given Apple SDK with CMake (Xcode generator),
# then merge ggml+whisper into one archive so the app links cleanly.
build_one() {
  local name="$1"
  local sysroot="$2"             # iphoneos | iphonesimulator | macosx
  local archs="$3"               # "arm64" or "arm64;x86_64"
  local deploy="$4"              # min version
  local cmake_system_name="$5"   # iOS or Darwin

  local bdir="${BUILD_DIR}/${name}"
  cmake -S "${WCPP}" -B "${bdir}" -G Xcode \
    -DCMAKE_SYSTEM_NAME="${cmake_system_name}" \
    -DCMAKE_OSX_SYSROOT="${sysroot}" \
    -DCMAKE_OSX_ARCHITECTURES="${archs}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${deploy}" \
    -DBUILD_SHARED_LIBS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_SERVER=OFF \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON

  cmake --build "${bdir}" --config Release

  # Xcode generator drops libs into:
  #   build/<name>/Release-<sdk>/*.a   OR Release/*.a for macOS depending on config
  local libdir=""
  if [ -d "${bdir}/Release-${sysroot}" ]; then
    libdir="${bdir}/Release-${sysroot}"
  elif [ -d "${bdir}/Release" ]; then
    libdir="${bdir}/Release"
  else
    echo "Could not find Release output dir for ${name}"
    exit 1
  fi

  # Try common library names used by whisper.cpp/ggml builds
  local whisper_a=""
  local ggml_a=""
  whisper_a="$(ls "${libdir}"/libwhisper*.a 2>/dev/null | head -n 1 || true)"
  ggml_a="$(ls "${libdir}"/libggml*.a 2>/dev/null | head -n 1 || true)"

  if [ -z "${whisper_a}" ]; then
    echo "No libwhisper*.a found in ${libdir}"
    ls -la "${libdir}" || true
    exit 1
  fi
  if [ -z "${ggml_a}" ]; then
    echo "No libggml*.a found in ${libdir}"
    ls -la "${libdir}" || true
    exit 1
  fi

  mkdir -p "${STAGE}/${name}"
  # Merge into a single archive
  libtool -static -o "${STAGE}/${name}/libWhisperCpp.a" "${whisper_a}" "${ggml_a}"
}

# Build per platform
build_one "ios" "iphoneos" "arm64" "${IOS_MIN}" "iOS"
build_one "iossim" "iphonesimulator" "arm64;x86_64" "${IOS_MIN}" "iOS"
build_one "macos" "macosx" "arm64;x86_64" "${MACOS_MIN}" "Darwin"

# Create xcframework
rm -rf "${OUT_DIR}/WhisperCpp.xcframework"
xcodebuild -create-xcframework \
  -library "${STAGE}/ios/libWhisperCpp.a" -headers "${HEADERS}" \
  -library "${STAGE}/iossim/libWhisperCpp.a" -headers "${HEADERS}" \
  -library "${STAGE}/macos/libWhisperCpp.a" -headers "${HEADERS}" \
  -output "${OUT_DIR}/WhisperCpp.xcframework"

echo "✅ Built ${OUT_DIR}/WhisperCpp.xcframework"
EOF
chmod +x Scripts/build_xcframework.sh

# Optional: a tiny convenience script
cat > Scripts/dev_build.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
IOS_MIN="${IOS_MIN:-14.0}" MACOS_MIN="${MACOS_MIN:-13.0}" ./Scripts/build_xcframework.sh
swift build
EOF
chmod +x Scripts/dev_build.sh

# GitHub Action to build the XCFramework on tag pushes (optional but useful)
cat > .github/workflows/build-xcframework.yml <<'EOF'
name: build-xcframework

on:
  push:
    tags:
      - "v*"

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - name: Build XCFramework
        run: |
          chmod +x Scripts/build_xcframework.sh
          Scripts/build_xcframework.sh
      - name: Zip XCFramework
        run: |
          cd Frameworks
          ditto -c -k --sequesterRsrc --keepParent WhisperCpp.xcframework WhisperCpp.xcframework.zip
      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: WhisperCpp.xcframework.zip
          path: Frameworks/WhisperCpp.xcframework.zip
EOF

# Final hints
cat > README.md <<EOF
# ${REPO_NAME}

SwiftPM wrapper around **whisper.cpp** as a local XCFramework.

## Dev
1) Build the XCFramework:
\`\`\`bash
./Scripts/build_xcframework.sh
\`\`\`

2) Build the Swift package:
\`\`\`bash
swift build
\`\`\`

## Notes
- This package references: \`Frameworks/WhisperCpp.xcframework\`
- Re-run the build script after updating \`vendor/whisper.cpp\`.
EOF

git add -A
echo "✅ Repo scaffolded."
echo
echo "Next:"
echo "  1) ./Scripts/build_xcframework.sh"
echo "  2) swift build"
echo
echo "If you want to change the pinned whisper.cpp version:"
echo "  WHISPERCPP_REF=<tag-or-commit> bash bootstrap.sh"