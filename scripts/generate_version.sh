#!/bin/bash
# Skript pro generování verze aplikace ve formátu rok.měsíc.minor
# Minor verze = počet commitů v aktuálním měsíci

YEAR=$(date +%Y)
MONTH=$(date +%m | sed 's/^0//')

# Počet commitů v aktuálním měsíci
MINOR=$(git log --since="$YEAR-$MONTH-01" --oneline 2>/dev/null | wc -l)
MINOR=$((MINOR + 1))

VERSION="$YEAR.$MONTH.$MINOR"
echo "$VERSION"
