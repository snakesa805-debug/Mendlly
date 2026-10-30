#!/usr/bin/env bash
# Builds android/build/UlarNeon.apk without Gradle: aapt2 -> javac -encoding UTF-8 -> d8 -> zipalign -> apksigner.
# Needs: JAVA_HOME (JDK 17) and ANDROID_SDK with platforms;android-34 and build-tools;34.0.0.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${ANDROID_SDK:-/tmp/sdk}"
BT="$SDK/build-tools/34.0.0"
JAR="$SDK/platforms/android-34/android.jar"
export JAVA_HOME="${JAVA_HOME:-$(ls -d /tmp/sdk/jdk-17* | head -1)}"
export PATH="$JAVA_HOME/bin:$PATH"
A="$ROOT/android"; B="$A/build"
rm -rf "$B"; mkdir -p "$B/res" "$B/gen" "$B/classes" "$B/assets/www"

node "$ROOT/tools/build_engine.js"
# Copy www, then protect own code: minify everything, obfuscate Mendlly's own scripts (UI, hub, settings).
cp -r "$ROOT"/www/. "$B/assets/www/"
node "$ROOT/tools/protect.js" "$B/assets/www"

"$BT/aapt2" compile --dir "$A/res" -o "$B/res/res.zip"
"$BT/aapt2" link -I "$JAR" --manifest "$A/AndroidManifest.xml" -A "$B/assets" \
  --java "$B/gen" -o "$B/unsigned.apk" "$B/res/res.zip" --min-sdk-version 21 --target-sdk-version 34
javac -encoding UTF-8 -source 8 -target 8 -nowarn -cp "$JAR" -d "$B/classes" \
  $(find "$A/src" -name '*.java') $(find "$B/gen" -name '*.java') 2>&1 | grep -v 'bootstrap classpath' || true
"$BT/d8" --lib "$JAR" --min-api 21 --output "$B" $(find "$B/classes" -name '*.class')
python3 -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1],'a',zipfile.ZIP_DEFLATED); z.write(sys.argv[2],'classes.dex'); z.close()" "$B/unsigned.apk" "$B/classes.dex"
"$BT/zipalign" -f -p 4 "$B/unsigned.apk" "$B/aligned.apk"
# Signing: values come from keystore.properties (not in the repo). See keystore.properties.example.
PROPS="$ROOT/keystore.properties"
if [ ! -f "$PROPS" ]; then echo "keystore.properties missing: copy keystore.properties.example and fill it (ask the owner for the original keystore)" >&2; exit 1; fi
prop() { grep -E "^$1=" "$PROPS" | head -1 | cut -d= -f2-; }
KS="$(prop storeFile)"; case "$KS" in /*) ;; *) KS="$ROOT/$KS";; esac
[ -f "$KS" ] || { echo "keystore not found: $KS" >&2; exit 1; }
"$BT/apksigner" sign --ks "$KS" --ks-pass "pass:$(prop storePassword)" --key-pass "pass:$(prop keyPassword)" --ks-key-alias "$(prop keyAlias)" \
  --out "$B/UlarNeon.apk" "$B/aligned.apk"
"$BT/apksigner" verify --print-certs "$B/UlarNeon.apk" | head -2
ls -la "$B/UlarNeon.apk"
