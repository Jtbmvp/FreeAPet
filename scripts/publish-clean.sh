#!/usr/bin/env bash
# Publica um snapshot limpo do trabalho local no ramo público, sem mexer no HEAD,
# no índice nem na árvore de trabalho. Uso: scripts/publish-clean.sh "mensagem" [--dry-run]
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
BRANCH=v3-integration
ALLOW=(src tests scripts sync docs assets AGENTS.md CLAUDE.md CONTRIBUTING.md README.md .gitignore
       default.project.json rokit.toml selene.toml stylua.toml .styluaignore)
MSG=${1:?falta a mensagem}; DRY=${2:-}
git fetch -q origin
BASE=$(git rev-parse -q --verify "origin/$BRANCH" || git rev-parse origin/main)
export GIT_INDEX_FILE; GIT_INDEX_FILE=$(mktemp -u)
trap 'rm -f "$GIT_INDEX_FILE"' EXIT
git read-tree "$BASE"
git add -A -- "${ALLOW[@]}"
TREE=$(git write-tree)
FILES=$(git ls-tree -r --name-only "$TREE")
if grep -qE '(ghp_[A-Za-z0-9]{20,}|github_pat_|gho_[A-Za-z0-9]{20,}|sk-ant-|AKIA[0-9A-Z]{16}|_\|WARNING:-DO-NOT|BEGIN [A-Z ]*PRIVATE KEY|discord(app)?\.com/api/webhooks)' <(git grep -hIE 'ghp_|github_pat_|gho_|sk-ant-|AKIA|WARNING:-DO-NOT|PRIVATE KEY|api/webhooks' "$TREE" -- ':!scripts/publish-clean.sh' || true); then
  echo "ABORTADO: possível segredo no snapshot." >&2; exit 1
fi
BIG=$(git ls-tree -r -l "$TREE" | awk '$4>50000000')
[[ -z "$BIG" ]] || { echo "ABORTADO: ficheiros >50 MB:"; echo "$BIG"; exit 1; }
echo "base $BASE | $(wc -l <<<"$FILES") ficheiros | $(git diff-tree -r --name-only "$BASE" "$TREE" | wc -l) alterados"
[[ "$DRY" == "--dry-run" ]] && exit 0
[[ "$TREE" == "$(git rev-parse "$BASE^{tree}")" ]] && { echo "Sem alterações."; exit 0; }
COMMIT=$(printf '%s\n' "$MSG" | git commit-tree "$TREE" -p "$BASE")
git push origin "$COMMIT:refs/heads/$BRANCH"
echo "Publicado: $BRANCH @ $COMMIT"
