#!/bin/sh
# Chargement du fichier .env et déclaration des variables d'environnement

CURRENT_DIR="$(pwd)"

if [ -f "$CURRENT_DIR/.env" ]; then
    # shellcheck disable=SC2046
    export $(grep -v '^#' "$CURRENT_DIR/.env" | xargs)
fi
