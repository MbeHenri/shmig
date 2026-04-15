#!/usr/bin/env bash
# Chargement du fichier .env et déclaration des variables d'environnement

if [ -f ".env" ]; then
    # shellcheck disable=SC2046
    export $(grep -v '^#' ".env" | xargs)
fi
