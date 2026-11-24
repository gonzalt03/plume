# Plume

Petite app macOS de barre de menu : sélectionne du texte dans n'importe quelle application, une barre flottante apparaît et propose de le faire retravailler par Claude.

<img src="Resources/AppIcon-preview.png" width="128" alt="Icône Plume">

## Actions

| Action | Effet |
|---|---|
| Demander à Claude | Consigne libre sur le texte sélectionné |
| Corriger | Orthographe, grammaire, ponctuation, sans changer le style |
| Reformuler | Corrige et clarifie en gardant le sens et le ton |
| Traduire | Français vers anglais, sinon vers le français |
| Résumer | L'essentiel en quelques lignes |
| Raccourcir | Version plus concise |

Le panneau de résultat permet de copier la réponse en texte brut (⇧⌘C), de remplacer la sélection (⌘↩), de régénérer ou de demander un suivi (« plus formel », etc.). Échap ferme le panneau.

## Prérequis

- macOS 13 ou plus récent, Mac Apple Silicon
- [Claude Code](https://claude.com/claude-code) installé et connecté (`claude` dans `~/.local/bin`, `/opt/homebrew/bin` ou `/usr/local/bin`) : Plume appelle `claude -p`, donc utilise ton abonnement, sans clé API
- Outils en ligne de commande Xcode (`swiftc`, `iconutil`, `codesign`)

## Installation

### Depuis la release

Télécharger `Plume-1.0.zip` dans les [releases](https://github.com/gonzalt03/plume/releases), le décompresser et déplacer `Plume.app` dans `~/Applications`. L'app n'est pas notariée par Apple : au premier lancement, faire clic droit > Ouvrir, ou lever la quarantaine :

```bash
xattr -dr com.apple.quarantine ~/Applications/Plume.app
```

### Depuis les sources

```bash
./build.sh
```

Compile l'app, l'installe dans `~/Applications/Plume.app` et la lance. Au premier lancement, autoriser Plume dans **Réglages Système > Confidentialité et sécurité > Accessibilité** (nécessaire pour lire la sélection et coller le résultat).

### Garder l'autorisation entre deux compilations

Avec une signature ad hoc, macOS considère chaque build comme une nouvelle app et retire l'autorisation d'accessibilité. Pour l'éviter, créer une fois un certificat de signature local nommé `Plume` : `build.sh` l'utilise automatiquement s'il existe.

```bash
D=$(mktemp -d) && cd "$D"
printf '[req]\ndistinguished_name=dn\nprompt=no\nx509_extensions=ext\n[dn]\nCN=Plume\n[ext]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n' > cfg
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 -config cfg
openssl pkcs12 -export -legacy -inkey key.pem -in cert.pem -out plume.p12 -passout pass:plume
security import plume.p12 -k ~/Library/Keychains/login.keychain-db -P plume -T /usr/bin/codesign
cd - && rm -rf "$D"
```

## Fonctionnement

- Détection de la sélection : glisser, double ou triple clic, puis lecture via l'API d'accessibilité ; repli sur ⌘C avec restauration du presse-papiers (Chrome, apps Electron).
- Appel à Claude : `claude -p` sans réglages utilisateur, hooks, plugins, outils ni MCP, avec un prompt système dédié.
- Remplacement : collage (⌘V) dans l'app d'origine, puis restauration du presse-papiers.
- Le menu de la barre permet de désactiver la barre, de choisir le modèle (Haiku par défaut, Sonnet, Opus) et de lancer Plume à l'ouverture de session.
- Journal de diagnostic : `~/Library/Logs/Plume.log`.

## Contrôle avant publication

Le dépôt est public : un contrôle automatique bloque tout commit ou push contenant des données sensibles (clés privées, jetons d'API, mots de passe, chemins personnels, adresses e-mail autres que l'adresse noreply GitHub, fichiers `.p12`/`.pem`/`.env`/`.log`, fichiers de plus de 5 Mo).

```bash
git config core.hooksPath .githooks   # à faire une fois après le clone
scripts/check-public.sh all           # contrôle manuel de tout le dépôt
```

Des termes privés supplémentaires (un motif par ligne) peuvent être listés dans `.public-check-local`, fichier ignoré par git.

## Structure

- `Sources/main.swift` : toute l'app (AppKit + SwiftUI)
- `tools/make-icon.swift` : génération de l'icône et de l'icône de barre de menu
- `build.sh` : compilation, signature, installation
- `scripts/check-public.sh`, `.githooks/` : contrôle avant publication
