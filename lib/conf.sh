#!/usr/bin/env bash
# Configuration shmig (shmig.cfg, optionnel)

if [ -f "$SCRIPT_DIR/shmig.cfg" ]; then

    while IFS='=' read -r key value; do
        # Ignorer les non-variables SHMIG_*
        [[ "$key" =~ ^SHMIG_ ]] || continue

        # N'exporter que si pas déjà défini dans l'environnement
        if [ -z "${!key:-}" ]; then
            # shellcheck disable=SC2046
            export "$key"="$value"
        fi
    done < <(
        bash -c ". '$SCRIPT_DIR/shmig.cfg' && set" 2>/dev/null |
            grep '^SHMIG_'
    )
fi
