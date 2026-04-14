#!/bin/sh
# migrate.sh
# Point d'entrée principal. Source les libs dans l'ordre puis dispatche
# la commande demandée.
#
# Usage : ./migrate.sh <command> [argument]

set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

. "$SCRIPT_DIR/shmig.lib/env.sh"
. "$SCRIPT_DIR/shmig.lib/core.sh"
. "$SCRIPT_DIR/shmig.lib/hooks.sh"

help() {
    cat <<'HELP'
Usage: ./migrate.sh <command> [argument]

Commands:
  up                : applique toutes les migrations en attente
                      si migrations/.heads existe, part des têtes définies dedans
  apply <migration> : applique une migration spécifique (et ses dépendances)
  down <migration>  : rollback une migration spécifique (vérifie les dépendants)
  rollback-last     : rollback de la dernière migration appliquée
  status            : état succinct (appliqué / non appliqué)
  list              : liste détaillée avec groupement par heads
  help              : affiche cette aide

Hooks (optionnels, dans hooks/) :
  pre-up, post-up
  pre-apply, post-apply       reçoivent le nom de la migration en $1
  pre-down, post-down         reçoivent le nom de la migration en $1
  pre-rollback-last, post-rollback-last

Fichier migrations/.heads (optionnel) :
  Une migration par ligne. Lignes vides et commentaires (#) ignorés.
HELP
}

cmd="${1:-up}"
arg="${2:-}"
MIGRATE_CMD="$cmd"
MIGRATE_ARG="$arg"
export MIGRATE_CMD MIGRATE_ARG

case "$cmd" in
up)
    acquire_lock
    run_hook pre-up
    if [ -f "$HEADS_FILE" ]; then
        log "Fichier heads détecté"
        for h in $(get_heads); do
            echo "$h"
            apply_migration_iterative "$h"
        done
    else
        for m in $(list_migrations); do
            echo "$m"
            apply_migration_iterative "$m"
        done
    fi
    run_hook post-up
    ;;
apply)
    if [ -z "$arg" ]; then
        err "Spécifiez le nom de la migration à appliquer"
        exit 1
    fi
    acquire_lock
    run_hook pre-apply "$arg"
    apply_migration_iterative "$arg"
    run_hook post-apply "$arg"
    ;;
down)
    if [ -z "$arg" ]; then
        err "Spécifiez le nom de la migration à rollback"
        exit 1
    fi
    acquire_lock
    run_hook pre-down "$arg"
    rollback_migration "$arg"
    run_hook post-down "$arg"
    ;;
rollback-last)
    acquire_lock
    run_hook pre-rollback-last
    rollback_last
    run_hook post-rollback-last
    ;;
status)
    status | less -R -F -X
    ;;
list)
    lists | less -R -F -X
    ;;
help | --help | -h)
    help
    ;;
*)
    err "Commande inconnue: $cmd"
    help
    exit 1
    ;;
esac
