#!/bin/zsh
# Builds TDLib (BSL-1.0) and its OpenSSL dependency from pinned tags into a
# static XCFramework for iOS.
#
# Compiled from source on purpose: TDLib is the component that holds our
# MTProto session, and taking an unofficial prebuilt binary of it would put a
# supply chain we do not control between the user and Telegram.
#
#   ./Scripts/build-tdlib.sh ssl        # OpenSSL for iphoneos + simulator
#   ./Scripts/build-tdlib.sh native     # TDLib API source generation on host
#   ./Scripts/build-tdlib.sh device     # cross-compile iphoneos/arm64
#   ./Scripts/build-tdlib.sh sim        # cross-compile iphonesimulator/arm64
#   ./Scripts/build-tdlib.sh framework  # assemble tdlib.xcframework
#   ./Scripts/build-tdlib.sh all
set -euo pipefail

TD_TAG="${TD_TAG:-v1.8.0}"
SSL_TAG="${SSL_TAG:-openssl-3.5.9}"
IOS_MIN="${IOS_MIN:-17.0}"
ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
VENDOR="$ROOT/Vendor"
SRC="$VENDOR/src/td"
SSL_SRC="$VENDOR/src/openssl"
JOBS="$(sysctl -n hw.ncpu)"

# tdjson_static pulls in tdjson_private/tdapi/tdclient/tddb/tdtelegram/tdnet/
# tdutils/tdtl/tdactor/tdsqlite, so every .a in the build dir gets merged in
# phase_framework; linking only libtdjson_static.a would leave symbols missing.
COMMON_ARGS=(
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5   # CMake 4 refuses tdlib's 3.0.2 minimum
  -DCMAKE_BUILD_TYPE=Release
  -DTD_ENABLE_JNI=OFF
  -DTD_ENABLE_DOTNET=OFF
  -DBUILD_SHARED_LIBS=OFF
)

fetch_source() {
  if [[ -d "$SRC/.git" ]]; then
    [[ "$(git -C "$SRC" describe --tags --always)" == "$TD_TAG" ]] && {
      echo "td source: $TD_TAG (cached)"; return; }
    rm -rf "$SRC"
  fi
  echo "cloning tdlib $TD_TAG"
  git clone --quiet --depth 1 --branch "$TD_TAG" https://github.com/tdlib/td.git "$SRC"
  echo "tdlib commit: $(git -C "$SRC" rev-parse HEAD)"
}

fetch_ssl_source() {
  if [[ -d "$SSL_SRC/.git" ]]; then
    [[ "$(git -C "$SSL_SRC" describe --tags --always)" == "$SSL_TAG" ]] && {
      echo "openssl source: $SSL_TAG (cached)"; return; }
    rm -rf "$SSL_SRC"
  fi
  echo "cloning openssl $SSL_TAG"
  git clone --quiet --depth 1 --branch "$SSL_TAG" https://github.com/openssl/openssl.git "$SSL_SRC"
  echo "openssl commit: $(git -C "$SSL_SRC" rev-parse HEAD)"
}

# $1 = Configure target (ios64-xcrun | iossimulator-arm64-xcrun), $2 = sdk
phase_ssl() {
  local target="$1" sdk="$2" arch="$3"
  local out="$VENDOR/ssl/$sdk-$arch" bdir="$VENDOR/build/ssl-$sdk-$arch"
  if [[ -f "$out/lib/libcrypto.a" ]]; then
    echo "openssl $sdk/$arch cached"; return
  fi
  fetch_ssl_source
  rm -rf "$bdir"; mkdir -p "$out" "$bdir"
  # Out-of-source: OpenSSL writes its makefile into the build dir.
  # `no-deprecated` is deliberately NOT passed: TDLib calls HMAC_Init_ex,
  # which OpenSSL 3.x deprecates but has not removed.
  ( cd "$bdir"
    "$SSL_SRC/Configure" "$target" \
      --prefix="$out" --openssldir="$out/ssl" \
      no-shared no-tests no-apps no-dso no-engine \
      -m"$sdk"-version-min="$IOS_MIN" \
      > "$VENDOR/log-openssl-configure.txt" 2>&1
    make -j "$JOBS" > "$VENDOR/log-openssl-build.txt" 2>&1
    make install_dev > /dev/null
  )
  echo "openssl built: $out/lib/libcrypto.a $(du -h "$out/lib/libcrypto.a" | cut -f1)"
}

# TDLib only emits its generated API sources when NOT cross-compiling (the
# if (NOT CMAKE_CROSSCOMPILING) guard in td/generate/CMakeLists.txt), and it
# writes them into the *source* tree, because those custom targets run with
# WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}. One native run therefore fills
# td/generate/auto/ for every iOS build below.
#
# README's `php SplitSource.php` is skipped deliberately: it exists for low-RAM
# machines and it rewrites files that CMake already listed at configure time.
phase_native() {
  fetch_source
  if [[ -f "$SRC/td/generate/auto/td/telegram/td_api.cpp" ]]; then
    echo "generated API sources already present, skipping"
    return
  fi
  cmake -S "$SRC" -B "$VENDOR/build/native" "${COMMON_ARGS[@]}" >/dev/null
  cmake --build "$VENDOR/build/native" --target prepare_cross_compiling -j "$JOBS"
  echo "generated API sources: $(find "$SRC/td/generate/auto" -type f | wc -l | tr -d ' ') files"
}

# $1 = sdk, $2 = arch
phase_sdk() {
  local sdk="$1" arch="$2"
  local bdir="$VENDOR/build/$sdk-$arch" ssl="$VENDOR/ssl/$sdk-$arch"
  [[ -f "$bdir/td/libtdjson_static.a" ]] && { echo "$sdk/$arch cached"; return; }
  [[ -f "$ssl/lib/libcrypto.a" ]] || { echo "run the ssl phase first ($sdk)"; exit 1; }
  rm -rf "$bdir"
  cmake -S "$SRC" -B "$bdir" "${COMMON_ARGS[@]}" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sdk" \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_MIN" \
    -DOPENSSL_ROOT_DIR="$ssl" \
    -DOPENSSL_INCLUDE_DIR="$ssl/include" \
    -DOPENSSL_SSL_LIBRARY="$ssl/lib/libssl.a" \
    -DOPENSSL_CRYPTO_LIBRARY="$ssl/lib/libcrypto.a" \
    -DCMAKE_C_FLAGS="-fPIC" -DCMAKE_CXX_FLAGS="-fPIC" >/dev/null
  cmake --build "$bdir" --target tdjson_static -j 8
  echo "built tdlib for $sdk/$arch"
}

# Headers Swift binds against: the JSON C client, plus a modulemap so the
# xcframework is importable without a bridging header.
phase_headers() {
  local inc="$VENDOR/td/include"
  rm -rf "$inc"; mkdir -p "$inc"
  find "$SRC/td" -name 'td_json_client.h' -o -name 'td_json_client_option.h' -o -name 'td_json_client_result.h' |
    while read -r h; do cp "$h" "$inc/"; done
  cat > "$inc/module.modulemap" <<'MODULEMAP'
module TdLibC [system] {
  header "td_json_client.h"
  header "td_json_client_option.h"
  export *
}
MODULEMAP
  echo "headers: $(/bin/ls "$inc" | tr '\n' ' ')"
}

phase_framework() {
  local out="$VENDOR/td/tdlib.xcframework"
  rm -rf "$out"
  phase_headers
  local args=()
  for bdir in "$VENDOR/build"/iphone*/; do
    local name merged
    name="$(basename "$bdir")"
    [[ -d "$bdir" ]] || continue
    local libs=("${(@f)$(find "$bdir" -name 'lib*.a' -not -path '*CMakeFiles*' | sort)}")
    # OpenSSL is merged in so the xcframework links standalone: tdlib's crypto
    # lives in libcrypto and libssl, which are not rebuilt by the tdlib target.
    local ssl_dir="$VENDOR/ssl/$name"
    libs+=("$ssl_dir/lib/libssl.a" "$ssl_dir/lib/libcrypto.a")
    for l in "${libs[@]}"; do
      [[ -f "$l" ]] || { echo "missing $l"; exit 1; }
    done
    merged="$VENDOR/td/$name-libtdlib.a"
    xcrun libtool -static -o "$merged" "${libs[@]}"
    echo "merged ${#libs[@]} libs -> $merged ($(/bin/ls -h "$merged" | awk '{print $5}'))"
    args+=(-library "$merged" -headers "$VENDOR/td/include")
  done
  [[ ${#args[@]} -gt 0 ]] || { echo "nothing to package; run device/sim first" >&2; exit 1; }
  xcodebuild -create-xcframework "${args[@]}" -output "$out"
  echo "xcframework: $out"
}

case "${1:-all}" in
  ssl)       phase_ssl ios64-xcrun iphoneos arm64; phase_ssl iossimulator-arm64-xcrun iphonesimulator arm64 ;;
  native)    phase_native ;;
  device)    phase_native; phase_sdk iphoneos arm64 ;;
  sim)       phase_native; phase_sdk iphonesimulator arm64 ;;
  ios)       phase_native; phase_sdk iphoneos arm64; phase_sdk iphonesimulator arm64 ;;
  framework) phase_framework ;;
  all)       phase_ssl ios64-xcrun iphoneos arm64
             phase_ssl iossimulator-arm64-xcrun iphonesimulator arm64
             phase_native
             phase_sdk iphoneos arm64
             phase_sdk iphonesimulator arm64
             phase_framework ;;
  *)         echo "usage: $0 [ssl|native|device|sim|ios|framework|all]" >&2; exit 2 ;;
esac
