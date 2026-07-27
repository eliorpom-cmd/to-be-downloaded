#!/usr/bin/env bash
#
# Régénère l'icône de l'app à partir du tracé vectoriel du logo.
# À relancer si `MascotShape` change.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"

cd "$ROOT"
# Le fichier d'entrée DOIT s'appeler main.swift pour que du code au premier
# niveau soit accepté dans une compilation multi-fichiers.
cp scripts/make-icon.swift "$WORK/main.swift"
# Compilé avec Mascot.swift : le tracé du logo n'existe qu'à un seul endroit.
swiftc -O -o "$WORK/make-icon" "$WORK/main.swift" App/Sources/Mascot.swift App/Sources/Theme.swift
"$WORK/make-icon"
