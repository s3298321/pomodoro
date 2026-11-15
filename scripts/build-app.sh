#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

sdk_src="$(cd /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk && pwd -P)"
cache="$root/.build/toolchain"
sdk="$cache/MacOSX.sdk"
overlay="$cache/bridging-overlay.json"
empty_map="$cache/empty.modulemap"
stamp="$cache/compiler-version"
compiler_line="$(swiftc --version | head -1)"

if [ ! -f "$stamp" ] || [ "$(cat "$stamp")" != "$compiler_line" ]; then
  rm -rf "$sdk"
  mkdir -p "$cache"
  cp -cR "$sdk_src" "$sdk" 2>/dev/null || cp -R "$sdk_src" "$sdk"
  compiler_id="$(printf '%s\n' "$compiler_line" | sed -n 's/.*(\(swiftlang-[^)]*\)).*/\1/p')"
  find "$sdk" -name '*.swiftinterface' -print0 | xargs -0 sed -i '' "s/swiftlang-[^)]*/${compiler_id}/"
  printf '// Avoid a duplicate SwiftBridging module map in this Command Line Tools install.\n' > "$empty_map"
  cat > "$overlay" << EOF
{
  "version": 0,
  "roots": [
    {
      "type": "file",
      "name": "/Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap",
      "external-contents": "$empty_map"
    }
  ]
}
EOF
  printf '%s\n' "$compiler_line" > "$stamp"
fi

if [ "$(uname -m)" = "arm64" ]; then
  arch="arm64e"
else
  arch="x86_64"
fi

swiftc_flags=(
  -swift-version 5
  -target "${arch}-apple-macosx15.4"
  -sdk "$sdk"
  -vfsoverlay "$overlay"
  -Xcc -ivfsoverlay
  -Xcc "$overlay"
)

echo "Running model tests"
swiftc "${swiftc_flags[@]}" -D TEST_RUNNER \
  -framework Foundation \
  "$root/Pomodoro/PomodoroModel.swift" \
  "$root/PomodoroTests/PomodoroModelTests.swift" \
  -o "$cache/pomodoro-model-tests"
"$cache/pomodoro-model-tests"

echo "Building Pomodoro.app"
app="$root/Pomodoro.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
swiftc "${swiftc_flags[@]}" \
  -framework AppKit \
  -framework SwiftUI \
  "$root"/Pomodoro/*.swift \
  "$root/PomodoroApp/main.swift" \
  -o "$app/Contents/MacOS/Pomodoro"
cp "$root/Info.plist" "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "$app"
