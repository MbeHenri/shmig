# shmig

Systeme visant a gerer les migrations en programmation systeme (en shell/bash/sh)

## Sommaire

- [shmig](#shmig)
  - [Sommaire](#sommaire)
  - [Fonctionnalités](#fonctionnalités)
  - [Arborescence](#arborescence)
  - [Installation](#installation)
  - [Écrire une migration](#écrire-une-migration)
  - [Dépendances entre migrations](#dépendances-entre-migrations)
  - [Fichier `.heads`](#fichier-heads)
  - [Hooks](#hooks)
    - [Hooks disponibles](#hooks-disponibles)
    - [Variables d'environnement dans les hooks](#variables-denvironnement-dans-les-hooks)
    - [Comportement en cas d'échec](#comportement-en-cas-déchec)
    - [Exemple : sauvegarde avant migration](#exemple--sauvegarde-avant-migration)
    - [Exemple : notification Slack après migration](#exemple--notification-slack-après-migration)
  - [Commandes](#commandes)
  - [Bonnes pratiques](#bonnes-pratiques)

## Fonctionnalités

- **Dépendances explicites** déclarées dans chaque script (`# depends_on=...`)
- **Résolution automatique** des dépendances par récursion avant chaque application
- **Rollback** par migration (`down`) ou du dernier appliqué (`rollback-last`)
- **Fichier `.heads`** pour définir les migrations racines d'un graphe de dépendances
- **Hooks** `pre`/`post` par commande pour étendre le comportement sans toucher au cœur
- **Graphe ASCII** des dépendances (`graph`)
- **Verrou d'exécution** pour éviter les exécutions concurrentes
- **Historique** persistant des migrations appliquées

## Arborescence

```txt
.
├── migrate.sh                  # Point d'entrée principal
├── lib/
│   ├── env.sh                  # Chargement .env et variables d'environnement
│   ├── core.sh                 # Logique métier des migrations
│   └── hooks.sh                # Système de hooks pre/post
├── hooks/                      # Scripts de hooks (optionnels, exécutables)
│   ├── pre-up
│   ├── post-up
│   ├── pre-apply
│   ├── post-apply
│   ├── pre-down
│   ├── post-down
│   ├── pre-rollback-last
│   └── post-rollback-last
├── migrations/                 # Scripts de migration
│   ├── .heads                  # Migrations racines du graphe (optionnel mais recommande)
│   ├── 001-init.sh
│   ├── 002-create-users.sh
│   └── 003-add-users-index.sh
├── migration_datas/            # Données auxiliaires pour les migrations
├── .migrations_history         # Historique des migrations appliquées
└── .migrations_lock            # Verrou d'exécution (supprimé automatiquement)
```

## Installation

```bash
# Cloner ou copier les fichiers dans votre projet
chmod +x migrate.sh migrations/*.sh

# Optionnel : copier un fichier .env.example vers .env pour les variables d'environnement
cp .env.example .env
```

## Écrire une migration

Chaque migration est un script shell avec deux actions : `up` (appliquer) et `down` (annuler).

```bash
#!/usr/bin/env bash
set -e
# depends_on=001-init.sh

if [ -z "${1-}" ] || [ "${1-}" = "up" ]; then
    echo "[002] up -> création de la collection users"
    cat > ./data/users.json <<JSON
[{"id":1,"name":"admin"}]
JSON
    exit 0
fi

if [ "${1-}" = "down" ]; then
    echo "[002] down -> suppression de la collection users"
    rm -f ./data/users.json || true
    exit 0
fi
```

Quelques exemples de commandes `up`/`down` selon la cible :

| Cible              | Exemple `up`                                           | Exemple `down`                              |
| ------------------ | ------------------------------------------------------ | ------------------------------------------- |
| MySQL / MariaDB    | `mysql -u$DB_USER ... < schema.sql`                    | `mysql -u$DB_USER ... -e "DROP TABLE ..."`  |
| PostgreSQL         | `psql $DATABASE_URL -f migration.sql`                  | `psql $DATABASE_URL -e "DROP TABLE ..."`    |
| MongoDB            | `mongosh $MONGO_URI --eval "db.createCollection(...)"` | `mongosh $MONGO_URI --eval "db.col.drop()"` |
| Fichiers / données | `mkdir -p ./data && cp seed.json ./data/`              | `rm -rf ./data/`                            |

> Utilise toujours des variables d'environnement pour les identifiants de connexion — ne les écris jamais en dur dans les scripts.

## Dépendances entre migrations

Déclare les dépendances en tête de script avec un commentaire `# depends_on=` :

```bash
# depends_on=001-init.sh
# depends_on=002-create-users.sh,001-init.sh   # plusieurs dépendances séparées par virgule
```

Il est important de precise que une dependance est un chemins relatif du script shell de la migration correspondante.
Il est relatif par rapport au repertoire `migrations`.

## Fichier `.heads`

Le fichier `migrations/.heads` permet de déclarer explicitement les migrations racines du graphe (celles dont aucune autre ne dépend). Quand il est présent :

- `./migrate.sh up` n'applique que les chaînes issues des têtes déclarées

```text
# migrations/.heads
# Une migration par ligne. Lignes vides et commentaires (#) ignorés.
003-add-users-index.sh
004-add-roles.sh
```

Sans ce fichier, `up` applique toutes les migrations détectées dans `migrations/`.

## Hooks

Des scripts optionnels placés dans `hooks/` permettent d'étendre le comportement de shmig sans modifier son code. Chaque hook doit être exécutable (`chmod +x`).

### Hooks disponibles

| Hook                 | Moment                              | Arguments                  |
| -------------------- | ----------------------------------- | -------------------------- |
| `pre-up`             | Avant l'application globale         | —                          |
| `post-up`            | Après l'application globale         | —                          |
| `pre-apply`          | Avant l'application d'une migration | `$1` = nom de la migration |
| `post-apply`         | Après l'application d'une migration | `$1` = nom de la migration |
| `pre-down`           | Avant le rollback d'une migration   | `$1` = nom de la migration |
| `post-down`          | Après le rollback d'une migration   | `$1` = nom de la migration |
| `pre-rollback-last`  | Avant le rollback du dernier        | —                          |
| `post-rollback-last` | Après le rollback du dernier        | —                          |

### Variables d'environnement dans les hooks

| Variable      | Description                                                |
| ------------- | ---------------------------------------------------------- |
| `MIGRATE_CMD` | Commande en cours (`up`, `apply`, `down`, `rollback-last`) |
| `MIGRATE_ARG` | Argument de la commande (nom de migration, ou vide)        |

### Comportement en cas d'échec

Si un hook retourne un code différent de `0`, l'exécution est **bloquée** (comme Git). La commande principale n'est pas lancée pour les hooks `pre-*`, ou le post-traitement est annulé pour les hooks `post-*`.

### Exemple : sauvegarde avant migration

```bash
# hooks/pre-up
#!/bin/sh
echo "[hook] Sauvegarde de la base avant migration..."
./scripts/backup.sh || exit 1
```

### Exemple : notification Slack après migration

```bash
# hooks/post-up
#!/bin/sh
curl -s -X POST "$SLACK_WEBHOOK" \
  -H 'Content-type: application/json' \
  -d '{"text":"✔ Migrations appliquées avec succès"}' || true
```

---

## Commandes

```bash
# Appliquer toutes les migrations en attente
./migrate.sh up

# Appliquer une migration spécifique (applique ses dépendances si nécessaire)
./migrate.sh apply 003-add-users-index.sh

# Rollback d'une migration spécifique
./migrate.sh down 003-add-users-index.sh

# Rollback de la dernière migration appliquée
./migrate.sh rollback-last

# État succinct de toutes les migrations
./migrate.sh status

# Liste détaillée avec groupement par heads
./migrate.sh list

# Aide
./migrate.sh help
```

---

## Bonnes pratiques

**Idempotence** — rends les actions `up` et `down` idempotentes autant que possible. Une migration appliquée deux fois ou annulée sans avoir été appliquée ne doit pas provoquer d'erreur.

```bash
# Exemple idempotent avec MySQL
mysql ... -e "CREATE TABLE IF NOT EXISTS users (...)"
mysql ... -e "DROP TABLE IF EXISTS users"
```

**Nommage** — préfixe les scripts par un numéro triable (`001-`, `002-`). Le mécanisme de dépendances rend l'ordre strict facultatif, mais un nommage cohérent facilite la lecture.

**Dépendances** — déclare toujours les dépendances explicitement, même si l'ordre alphabétique les garantirait. C'est de la documentation autant qu'une contrainte technique.

**Rollback** — fournis toujours la logique `down` dans chaque script, même si elle se limite à un commentaire expliquant pourquoi elle est intentionnellement vide.

**Sécurité** — ne stocke jamais de mots de passe en clair dans les scripts. Utilise des variables d'environnement ou un gestionnaire de secrets.

**Hooks** — garde les hooks légers et ciblés (sauvegarde, notification, validation). Une logique métier lourde appartient aux scripts de migration eux-mêmes.
