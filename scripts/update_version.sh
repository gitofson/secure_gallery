#!/bin/bash
# Skript pro aktualizaci verze v pubspec.yaml před buildem

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PUBSPEC="$PROJECT_DIR/pubspec.yaml"

# Generování nové verze
NEW_VERSION=$("$SCRIPT_DIR/generate_version.sh")
BUILD_NUMBER=$(echo "$NEW_VERSION" | cut -d. -f3)

echo "Aktualizuji verzi na: $NEW_VERSION+$BUILD_NUMBER"

# Aktualizace pubspec.yaml
sed -i "s/^version: .*/version: $NEW_VERSION+$BUILD_NUMBER/" "$PUBSPEC"

echo "Verze aktualizována v $PUBSPEC"
