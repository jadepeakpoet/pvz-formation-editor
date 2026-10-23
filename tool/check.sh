#!/bin/sh
# Focused checks, including real Flutter engine tests without a local VM-service socket.
set -eu
sdk_path=${FLUTTER_SDK:-$(dirname "$(dirname "$(command -v flutter)")")}
engine_path=${FLUTTER_ENGINE_DIR:-$sdk_path/bin/cache/artifacts/engine/darwin-x64}
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/pvz-check.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT HUP INT TERM
"$sdk_path/bin/dart" run tool/catalog.dart --check
"$sdk_path/bin/flutter" analyze
"$sdk_path/bin/dart" test test/formation_test.dart test/storage_test.dart test/website_codec_test.dart test/original_catalog_test.dart test/layout_actions_test.dart --reporter expanded
"$sdk_path/bin/flutter" build bundle --debug --no-pub
for smoke in render session ui; do
  "$sdk_path/bin/cache/dart-sdk/bin/dart" \
    "$sdk_path/bin/cache/dart-sdk/bin/snapshots/frontend_server.dart.snapshot" \
    --sdk-root "$sdk_path/bin/cache/artifacts/engine/common/flutter_patched_sdk" \
    --target=flutter --packages .dart_tool/package_config.json \
    --output-dill "$check_dir/$smoke.dill" "tool/${smoke}_smoke.dart" > "$check_dir/$smoke.compile.log" 2>&1
  if [ ! -f "$check_dir/$smoke.dill" ] || ! awk 'END {exit !($NF == 0 && $(NF-1) ~ /\.dill$/)}' "$check_dir/$smoke.compile.log"; then
    cat "$check_dir/$smoke.compile.log"
    exit 1
  fi
  "$engine_path/flutter_tester" --disable-vm-service --run-forever \
    --enable-software-rendering --flutter-assets-dir=build/flutter_assets "$check_dir/$smoke.dill"
done
