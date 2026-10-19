#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != Darwin ]]; then
  echo "Building the iOS runtime requires macOS and Xcode. Use test-manga-runtime.sh on Linux."
  exit 2
fi
mkdir -p build
if ! command -v rustup >/dev/null; then
  curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs -o build/rustup-init.sh
  sh build/rustup-init.sh -y --profile minimal --default-toolchain 1.99.1
fi
source "$HOME/.cargo/env"
rustup toolchain install 1.99.1 --profile minimal
python3 scripts/prepare-manga-interpreter.py
python3 scripts/manga-licenses.py
rustup target add --toolchain 1.99.1 aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
export IPHONEOS_DEPLOYMENT_TARGET=17.0
export LIBCLANG_PATH="$(dirname "$(xcrun --find clang)")/../lib"
manifest="Tools/MangaRuntime/Cargo.toml"
for target in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
  case "$target" in
    aarch64-apple-ios) sdk=iphoneos; clang_target=arm64-apple-ios17.0 ;;
    aarch64-apple-ios-sim) sdk=iphonesimulator; clang_target=arm64-apple-ios17.0-simulator ;;
    x86_64-apple-ios) sdk=iphonesimulator; clang_target=x86_64-apple-ios17.0-simulator ;;
  esac
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
  SDKROOT="$sdk_path" BINDGEN_EXTRA_CLANG_ARGS="--target=$clang_target -isysroot $sdk_path" \
    cargo +1.99.1 build --locked --release --manifest-path "$manifest" --target "$target" -j 3
done
xcrun lipo -create \
  Tools/MangaRuntime/target/aarch64-apple-ios-sim/release/libanime_manga_runtime.a \
  Tools/MangaRuntime/target/x86_64-apple-ios/release/libanime_manga_runtime.a \
  -output build/libMangaRuntime-simulator.a
rm -rf build/MangaRuntime.xcframework
xcodebuild -create-xcframework \
  -library Tools/MangaRuntime/target/aarch64-apple-ios/release/libanime_manga_runtime.a \
  -headers Tools/MangaRuntime/include \
  -library build/libMangaRuntime-simulator.a -headers Tools/MangaRuntime/include \
  -output build/MangaRuntime.xcframework
