#!/usr/bin/env bash
# Variables propres aux migrations et logique métier complète.
# Dépend des variables définies dans lib/env.sh.

MIGRATIONS_DIR="${SHMIG_MIGRATIONS_DIR:-"${SCRIPT_DIR}/.shmig.migrations"}"
HISTORY_FILE="${SHMIG_HISTORY_FILE:-"${SCRIPT_DIR}/.shmig.history"}"
LOCK_DIR="${SHMIG_LOCK_DIR:-"${SCRIPT_DIR}/.shmig.lock"}"
HEADS_FILE="$MIGRATIONS_DIR/.heads"


echo "$MIGRATIONS_DIR"

mkdir -p "$MIGRATIONS_DIR"
if [ ! -f "$HISTORY_FILE" ]; then
    touch "$HISTORY_FILE"
fi

# ---------------------------------------------------------------------------
# Utilitaires
# ---------------------------------------------------------------------------

log() { printf "[migrate] %s\n" "$1"; }
err() { printf "[migrate] ERROR: %s\n" "$1" >&2; }

acquire_lock() {
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        trap 'rm -rf "$LOCK_DIR"' EXIT
    else
        err "Une autre instance est en cours. Si ce n'est pas le cas, supprimez $LOCK_DIR manuellement."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Historique
# ---------------------------------------------------------------------------

is_applied() {
    local mig="$1"
    [ -f "$HISTORY_FILE" ] || return 1
    grep -Fxq "$mig" "$HISTORY_FILE" 2>/dev/null || return 1
}

record_applied() {
    printf '%s\n' "$1" >>"$HISTORY_FILE"
}

remove_from_history() {
    local mig="$1"
    grep -Fxv "$mig" "$HISTORY_FILE" >"$HISTORY_FILE.tmp" || true
    mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
}

# ---------------------------------------------------------------------------
# Découverte et parsing
# ---------------------------------------------------------------------------

list_migrations() {
    if [ -z "$(find "$MIGRATIONS_DIR" -type f -name "*.sh")" ]; then
        echo ""
    fi
    find "$MIGRATIONS_DIR" -type f -name "*.sh" | sed "s|^$MIGRATIONS_DIR/||" | sort
}

parse_dependencies() {
    local migfile="$1"
    local deps
    deps=$(grep -E '^#\s*depends_on=' "$MIGRATIONS_DIR/$migfile" || true)
    if [ -z "$deps" ]; then
        echo ""
        return
    fi
    deps=${deps#*=}
    deps=$(echo "$deps" | tr -d ' ' | tr -d '"' | tr -d "'")
    deps=$(echo "$deps" | tr ',' ' ')
    echo "$deps"
}

# Retourne les têtes définies dans HEADS_FILE (migrations racines).
# Si HEADS_FILE n'existe pas, retourne une chaîne vide.
get_heads() {
    if [ -f "$HEADS_FILE" ]; then
        local heads=""
        for head in $(grep -v '^\s*#' "$HEADS_FILE" | grep -v '^\s*$'); do
            if [ -f "$MIGRATIONS_DIR/$head" ]; then
                heads="$heads $head"
            fi
        done
        echo "$heads"
    else
        echo ""
    fi
}

# ---------------------------------------------------------------------------
# Application
# ---------------------------------------------------------------------------

apply_migration() {
    local mig="$1"

    if is_applied "$mig"; then
        log "Skipping $mig (déjà appliqué)"
        return 0
    fi

    if [ ! -f "$MIGRATIONS_DIR/$mig" ]; then
        err "Fichier de migration introuvable: $MIGRATIONS_DIR/$mig"
        exit 1
    fi

    local deps
    deps=$(parse_dependencies "$mig")
    for d in $deps; do
        [ -z "$d" ] && continue
        if ! is_applied "$d"; then
            log "$mig dépend de $d — application de $d d'abord"
            apply_migration "$d"
        fi
    done

    log "Applying $mig"
    chmod +x "$MIGRATIONS_DIR/$mig"
    bash "$MIGRATIONS_DIR/$mig"
    local rc=$?
    if [ $rc -ne 0 ]; then
        err "La migration $mig a échoué (code $rc)"
        exit $rc
    fi

    record_applied "$mig"
    log "$mig appliquée"
}

apply_migration_iterative() {
    local start_mig="$1"

    # pile principale
    local stack=()
    # pile pour marquer les migrations en cours de traitement
    local processing=()

    stack+=("$start_mig")

    while [ ${#stack[@]} -gt 0 ]; do
        # prendre le dernier élément (LIFO)
        local mig="${stack[-1]}"

        # si déjà appliquée → on skip
        if is_applied "$mig"; then
            log "Skipping $mig (déjà appliqué)"
            stack=("${stack[@]:0:${#stack[@]}-1}")
            continue
        fi

        # vérifier fichier
        if [ ! -f "$MIGRATIONS_DIR/$mig" ]; then
            err "Fichier de migration introuvable: $MIGRATIONS_DIR/$mig"
            exit 1
        fi

        # vérifier si déjà en cours de traitement
        if [[ " ${processing[*]} " =~ " $mig " ]]; then
            # toutes les dépendances sont supposées traitées → exécution
            log "Applying $mig"

            chmod +x "$MIGRATIONS_DIR/$mig"
            bash "$MIGRATIONS_DIR/$mig"
            local rc=$?

            if [ $rc -ne 0 ]; then
                err "La migration $mig a échoué (code $rc)"
                exit $rc
            fi

            record_applied "$mig"
            log "$mig appliquée"

            # retirer de la pile
            stack=("${stack[@]:0:${#stack[@]}-1}")
            continue
        fi

        # marquer comme en cours
        processing+=("$mig")

        # récupérer dépendances
        local deps
        deps=$(parse_dependencies "$mig")

        local has_unapplied_deps=0

        for d in $deps; do
            [ -z "$d" ] && continue

            if ! is_applied "$d"; then
                log "$mig dépend de $d — ajout dans la pile"
                stack+=("$d")
                has_unapplied_deps=1
            fi
        done

        # si aucune dépendance à traiter → exécution directe
        if [ $has_unapplied_deps -eq 0 ]; then
            log "Applying $mig"

            chmod +x "$MIGRATIONS_DIR/$mig"
            bash "$MIGRATIONS_DIR/$mig"
            local rc=$?

            if [ $rc -ne 0 ]; then
                err "La migration $mig a échoué (code $rc)"
                exit $rc
            fi

            record_applied "$mig"
            log "$mig appliquée"

            stack=("${stack[@]:0:${#stack[@]}-1}")
        fi
    done
}

# ---------------------------------------------------------------------------
# Rollback
# ---------------------------------------------------------------------------

rollback_migration() {
    local mig="$1"

    if ! is_applied "$mig"; then
        err "$mig n'est pas appliquée — rien à rollback"
        exit 1
    fi

    local applied
    applied=$(cat "$HISTORY_FILE")
    for am in $applied; do
        [ "$am" = "$mig" ] && continue
        local deps
        deps=$(parse_dependencies "$am")
        for d in $deps; do
            if [ "$d" = "$mig" ]; then
                err "Impossible de rollback $mig : $am dépend de $mig et est appliquée. Rollback $am d'abord."
                exit 1
            fi
        done
    done

    log "Rollback $mig"
    bash "$MIGRATIONS_DIR/$mig" down
    local rc=$?
    if [ $rc -ne 0 ]; then
        err "Rollback de $mig a échoué (code $rc)"
        exit $rc
    fi

    remove_from_history "$mig"
    log "$mig rollbackée"
}

rollback_last() {
    local last
    last=$(tail -n 1 "$HISTORY_FILE" || true)

    echo "last : $last"
    if [ -z "$last" ]; then
        log "Aucune migration appliquée à rollback"
        exit 0
    fi
    rollback_migration "$last"
}

# ---------------------------------------------------------------------------
# Affichage
# ---------------------------------------------------------------------------

lists() {
    log "Liste des Migrations :"

    local group_icon="\033[0;34m■\033[0m"
    local applied_icon="\033[0;32m✔\033[0m"

    if [ -f "$HEADS_FILE" ]; then
        printf "$group_icon %s\n" "Migrations racines (HEADS) :"
        for m in $(get_heads); do
            if is_applied "$m"; then
                printf "  [$applied_icon] %s\n" "$m"
            else
                printf "  [ ] %s\n" "$m"
            fi
        done
        printf "\n"
    fi

    printf "$group_icon %s\n" "Migrations détectées :"
    for m in $(list_migrations); do
        if is_applied "$m"; then
            printf "  [$applied_icon] %s\n" "$m"
        else
            printf "  [ ] %s\n" "$m"
        fi
    done
}

status() {
    log "Migrations disponibles :"
    for m in $(list_migrations); do
        if is_applied "$m"; then
            printf "  [X] %s\n" "$m"
        else
            printf "  [ ] %s\n" "$m"
        fi
    done
}
