#!/bin/bash
# Produit dist/Copiste-<version>.pkg, .dmg et .zip
# Prérequis : python3 (dmgbuild est installé automatiquement dans build/.venv).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
REPO_URL=${REPO_URL:-https://github.com/louisclauzier/Copiste}
DIST=dist
WORK=build/package
GUIDE_NAME="Guide d'installation.html"

./build.sh
rm -rf "$DIST" "$WORK"
mkdir -p "$DIST" "$WORK/root" "$WORK/scripts" "$WORK/guide"

# 1. Guide d'installation (HTML autonome, icône intégrée)
python3 -I - "$VERSION" "$REPO_URL" "$WORK/guide/$GUIDE_NAME" <<'PY'
import base64, subprocess, sys, tempfile, os
version, repo, out = sys.argv[1:4]
tmp = os.path.join(tempfile.mkdtemp(), "icon.png")
subprocess.run(["sips", "-z", "256", "256", "Resources/branding/icon-1024.png", "--out", tmp], check=True, capture_output=True)
icon = base64.b64encode(open(tmp, "rb").read()).decode()
html = open("installer/guide.html", encoding="utf-8").read()
html = html.replace("{{ICON}}", icon).replace("{{VERSION}}", version).replace("{{REPO_URL}}", repo)
open(out, "w", encoding="utf-8").write(html)
PY

# 2. Installeur .pkg
ditto build/Copiste.app "$WORK/root/Copiste.app"
pkgbuild --analyze --root "$WORK/root" "$WORK/component.plist" >/dev/null
# Toujours installer dans /Applications, même si une autre copie de Copiste existe ailleurs.
plutil -replace 0.BundleIsRelocatable -bool NO "$WORK/component.plist"
cp installer/scripts/preinstall installer/scripts/postinstall "$WORK/scripts/"
chmod +x "$WORK/scripts/"*
xattr -cr "$WORK/scripts" "$WORK/root"
pkgbuild --root "$WORK/root" --component-plist "$WORK/component.plist" \
         --identifier fr.louisclauzier.copiste.pkg --version "$VERSION" \
         --install-location /Applications --scripts "$WORK/scripts" \
         "$WORK/Copiste-component.pkg" >/dev/null
sed "s/__VERSION__/$VERSION/g" installer/distribution.xml > "$WORK/distribution.xml"
productbuild --distribution "$WORK/distribution.xml" --resources installer/resources \
             --package-path "$WORK" "$DIST/Copiste-$VERSION.pkg" >/dev/null
echo "✅ $DIST/Copiste-$VERSION.pkg"

# 3. Image disque .dmg
if ! command -v dmgbuild >/dev/null; then
    [ -x build/.venv/bin/dmgbuild ] || { python3 -m venv build/.venv && build/.venv/bin/pip install -q dmgbuild; }
    DMGBUILD=build/.venv/bin/dmgbuild
else
    DMGBUILD=dmgbuild
fi
"$DMGBUILD" -s installer/dmg_settings.py \
    -D app=build/Copiste.app -D guide="$WORK/guide/$GUIDE_NAME" \
    -D background=installer/dmg/dmg-background.tiff -D icon=Resources/AppIcon.icns \
    "Copiste" "$DIST/Copiste-$VERSION.dmg" >/dev/null
echo "✅ $DIST/Copiste-$VERSION.dmg"

# 4. Archive .zip : installeur .pkg + guide
ZIPDIR="$WORK/Copiste $VERSION"
mkdir -p "$ZIPDIR"
cp "$DIST/Copiste-$VERSION.pkg" "$WORK/guide/$GUIDE_NAME" "$ZIPDIR/"
ditto -c -k --norsrc --noextattr --keepParent "$ZIPDIR" "$DIST/Copiste-$VERSION.zip"
echo "✅ $DIST/Copiste-$VERSION.zip"

(cd "$DIST" && shasum -a 256 Copiste-"$VERSION".* > SHA256SUMS.txt)
ls -lh "$DIST"
