#!/bin/bash
# Compile Copiste et assemble build/Copiste.app
set -euo pipefail
cd "$(dirname "$0")"

# Binaire universel : Apple Silicon + Intel.
swift build -c release --triple arm64-apple-macosx14.0
swift build -c release --triple x86_64-apple-macosx14.0

APP="build/Copiste.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create .build/arm64-apple-macosx/release/Copiste .build/x86_64-apple-macosx/release/Copiste \
     -output "$APP/Contents/MacOS/Copiste"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# Signature stable (certificat Apple Development) : macOS conserve alors
# l'autorisation Accessibilité d'une compilation à l'autre. Sinon, signature ad hoc.
IDENTITY=$(security find-identity -p codesigning -v | grep -m1 -o '"Apple Development[^"]*"' | tr -d '"' || true)
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Signé avec : ${IDENTITY:-ad hoc}"

echo "✅ $APP"
