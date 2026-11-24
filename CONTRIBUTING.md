# Contribuer à Plume

## Compiler depuis les sources

Prérequis : outils en ligne de commande Xcode (`swiftc`, `iconutil`, `codesign`).

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

## Contrôle avant publication

Le dépôt est public : un contrôle automatique bloque tout commit ou push contenant des données sensibles (clés privées, jetons d'API, mots de passe, chemins personnels, adresses e-mail autres que l'adresse noreply GitHub, fichiers `.p12`/`.pem`/`.env`/`.log`, fichiers de plus de 5 Mo).

```bash
git config core.hooksPath .githooks   # à faire une fois après le clone
scripts/check-public.sh all           # contrôle manuel de tout le dépôt
```

Des termes privés supplémentaires (un motif par ligne) peuvent être listés dans `.public-check-local`, fichier ignoré par git.

## Publier une version

```bash
scripts/release.sh 1.2 notes.md
```

Met à jour la version, lance le contrôle avant publication, commit, tag, construit le DMG et crée la release GitHub. Les apps installées détectent la nouvelle release et proposent la mise à jour. Les releases doivent être signées avec le certificat `Plume` : une version signée autrement est refusée par le système de mise à jour.

## Structure

- `Sources/main.swift` : toute l'app (AppKit + SwiftUI)
- `tools/make-icon.swift` : génération de l'icône et de l'icône de barre de menu
- `build.sh` : compilation, signature, installation
- `scripts/make-dmg.sh` : image disque d'installation (nécessite `brew install create-dmg`)
- `scripts/release.sh <version> <notes.md>` : publication d'une version (DMG + release GitHub)
- `docs/demo.svg` : animation de démonstration
- `scripts/check-public.sh`, `.githooks/` : contrôle avant publication
