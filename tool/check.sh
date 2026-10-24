#!/bin/sh
# Focused checks, including real Flutter engine tests without a local VM-service socket.
set -eu
sdk_path=${FLUTTER_SDK:-$(dirname "$(dirname "$(command -v flutter)")")}
case "$(uname -s)" in
  Darwin) host_os=darwin ;;
  Linux) host_os=linux ;;
  *) echo "Use flutter test and the Windows build tools on this host." >&2; exit 1 ;;
esac
case "$(uname -m)" in
  arm64|aarch64) host_arch=arm64 ;;
  *) host_arch=x64 ;;
esac
engine_path=${FLUTTER_ENGINE_DIR:-$sdk_path/bin/cache/artifacts/engine/$host_os-$host_arch}
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/pvz-check.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT HUP INT TERM
"$sdk_path/bin/dart" run tool/catalog.dart --check
"$sdk_path/bin/flutter" analyze
"$sdk_path/bin/flutter" test --no-pub --reporter expanded
"$sdk_path/bin/flutter" build bundle --debug --no-pub
for smoke in render session ui; do
  "$sdk_path/bin/cache/dart-sdk/bin/dartaotruntime" \
    "$engine_path/frontend_server_aot.dart.snapshot" \
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
