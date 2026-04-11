#!/bin/sh
# Système de hooks exécutés avant/après chaque commande principale.
#
# Convention de nommage des fichiers dans hooks/ :
#   pre-<commande>         exécuté avant la commande
#   post-<commande>        exécuté après la commande
#
# Commandes hookables : up, apply, down, rollback-last
#
# Arguments transmis au hook :
#   pre-apply  <migration>    nom de la migration ciblée
#   post-apply <migration>    idem
#   pre-down   <migration>    idem
#   post-down  <migration>    idem
#   pre-up     (aucun)
#   post-up    (aucun)
#   pre-rollback-last  (aucun)
#   post-rollback-last (aucun)
#
# Variables d'environnement disponibles dans les hooks :
#   MIGRATE_CMD      commande en cours (up, apply, down, rollback-last)
#   MIGRATE_ARG      argument de la commande (nom de migration, ou vide)
#
# Comportement en cas d'échec :
#   Si le hook retourne un code != 0, l'exécution est bloquée (comportement Git).
#
# Exemple de hook hooks/pre-up :
#   #!/bin/sh
#   echo "[hook] Sauvegarde BD avant migration..."
#   ./backup.sh || exit 1

HOOKS_DIR="${SCRIPT_DIR}/hooks"

# run_hook <nom> [arg]
#   nom : ex. "pre-up", "post-apply"
#   arg : optionnel, transmis au script hook en $1
run_hook() {
    local name="$1"
    local arg="${2:-}"
    local hook_file="$HOOKS_DIR/$name"

    [ -f "$hook_file" ] || return 0

    log "Running hook $name${arg:+ ($arg)}"

    if [ -n "$arg" ]; then
        MIGRATE_CMD="$MIGRATE_CMD"
        MIGRATE_ARG="$arg"
        bash "$hook_file" "$arg"
    else
        MIGRATE_CMD="$MIGRATE_CMD"
        MIGRATE_ARG=""
        bash "$hook_file"
    fi

    local rc=$?
    if [ $rc -ne 0 ]; then
        err "Hook '$name' a échoué (code $rc) — exécution annulée"
        exit $rc
    fi
}
