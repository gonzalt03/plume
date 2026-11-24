#!/bin/bash
# Vérifie qu'aucune donnée sensible ne part dans ce dépôt public.
# Usage : scripts/check-public.sh staged   (contenu indexé, pour pre-commit)
#         scripts/check-public.sh push <range>  (commits à pousser, pour pre-push)
#         scripts/check-public.sh all      (tout le dépôt suivi)
# Termes privés supplémentaires (employeur, clients, projets...) : un motif par ligne
# dans .public-check-local (ignoré par git, jamais publié).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

MODE="${1:-staged}"
RANGE="${2:-}"
fail=0
report() { echo "✗ $1"; fail=1; }

# Motifs interdits dans le contenu.
PATTERNS=(
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  'sk-ant-[A-Za-z0-9_-]{10,}'
  'gh[pousr]_[A-Za-z0-9]{20,}'
  'github_pat_[A-Za-z0-9_]{20,}'
  'AKIA[0-9A-Z]{16}'
  'xox[abpr]-[A-Za-z0-9-]{10,}'
  'AIza[0-9A-Za-z_-]{30,}'
  '(api[_-]?key|secret|password|passwd)["'"'"' ]*[:=]["'"'"' ]*[A-Za-z0-9/+_-]{12,}'
  '/Users/[a-z]'
  '/home/[a-z]'
)
if [ -f .public-check-local ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && [ "${line:0:1}" != "#" ] && PATTERNS+=("$line")
  done < .public-check-local
fi

# Fichiers concernés.
case "$MODE" in
  staged) FILES=$(git diff --cached --name-only --diff-filter=ACMR) ;;
  push)   FILES=$(git diff --name-only --diff-filter=ACMR $RANGE 2>/dev/null) ;;
  all)    FILES=$(git ls-files) ;;
esac

content() {
  case "$MODE" in
    staged) git show ":$1" 2>/dev/null ;;
    *)      cat "$1" 2>/dev/null ;;
  esac
}

for f in $FILES; do
  # Fichiers sensibles par leur nom.
  if echo "$f" | grep -qiE '(\.p12|\.pem|\.key|\.cer|\.mobileprovision|\.env(\..*)?|\.log|credentials.*|id_rsa.*|\.public-check-local)$'; then
    report "$f : type de fichier sensible"
    continue
  fi
  # Fichiers volumineux.
  size=$(content "$f" | wc -c | tr -d ' ')
  [ "$size" -gt 5000000 ] && report "$f : fichier de plus de 5 Mo"
  # Contenu (texte uniquement).
  if content "$f" | grep -Iq . ; then
    for p in "${PATTERNS[@]}"; do
      hits=$(content "$f" | grep -nIiE -e "$p" | grep -v 'check-public' | head -3)
      [ -n "$hits" ] && report "$f : motif interdit « $p »
$hits"
    done
    # E-mails autres que noreply GitHub.
    mails=$(content "$f" | grep -oIiE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' | grep -viE 'users\.noreply\.github\.com|@example\.(com|org)|@[0-9]+x\.' | sort -u)
    [ -n "$mails" ] && report "$f : adresse e-mail $mails"
  fi
done

# Auteurs des commits à pousser : uniquement l'adresse noreply.
if [ "$MODE" = "push" ] && [ -n "$RANGE" ]; then
  bad=$(git log --format='%ae%n%ce' $RANGE | sort -u | grep -v 'users\.noreply\.github\.com$')
  [ -n "$bad" ] && report "commits avec une adresse non noreply : $bad"
fi

# Configuration locale de l'auteur.
email=$(git config user.email)
echo "$email" | grep -q 'users\.noreply\.github\.com$' || report "git config user.email = $email (attendu : adresse noreply GitHub)"

if [ $fail -ne 0 ]; then
  echo "Contrôle de publication échoué : corriger avant de continuer."
  exit 1
fi
echo "✓ Contrôle de publication OK"
