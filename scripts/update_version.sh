#!/bin/bash
# Skript pro aktualizaci verze v pubspec.yaml před buildem

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PUBSPEC="$PROJECT_DIR/pubspec.yaml"

# Generování nové verze
NEW_VERSION=$("$SCRIPT_DIR/generate_version.sh")

echo "Aktualizuji verzi na: $NEW_VERSION"

# Aktualizace pubspec.yaml
sed -i "s/^version: .*/version: $NEW_VERSION/" "$PUBSPEC"

echo "Verze aktualizována v $PUBSPEC"

# Sestavení APK
echo "Sestavuji APK..."
cd "$PROJECT_DIR"
export JAVA_HOME=/scratch/android-studio/jbr
/scratch/flutter/bin/flutter build apk --release

echo "✅ Hotovo! APK: $PROJECT_DIR/build/app/outputs/flutter-apk/app-release.apk"
