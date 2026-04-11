#!/bin/sh
# Chargement du fichier .env et déclaration des variables d'environnement

if [ -f "$SCRIPT_DIR/.env" ]; then
    # shellcheck disable=SC2046
    export $(grep -v '^#' "$SCRIPT_DIR/.env" | xargs)
fi
