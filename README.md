# Plume

Petite app macOS de barre de menu : sélectionne du texte dans n'importe quelle application, une barre flottante apparaît et propose de le faire retravailler par Claude.

<img src="Resources/AppIcon-preview.png" width="128" alt="Icône Plume">

![Démonstration : sélection d'un texte, action Corriger, remplacement](docs/demo.svg)

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

## Installation

1. Télécharger le `.dmg` de la [dernière release](https://github.com/gonzalt03/plume/releases/latest), l'ouvrir et glisser Plume sur le dossier Applications.
2. Au premier lancement, faire clic droit > Ouvrir (l'app n'est pas notariée par Apple), ou lever la quarantaine :

```bash
xattr -dr com.apple.quarantine /Applications/Plume.app
```

3. Autoriser Plume dans **Réglages Système > Confidentialité et sécurité > Accessibilité** (nécessaire pour lire la sélection et coller le résultat).

Plume se met ensuite à jour toute seule : elle vérifie les releases GitHub au lancement puis toutes les 24 h et propose d'installer la nouvelle version (menu « Rechercher les mises à jour… »).

## Fonctionnement

- Détection de la sélection : glisser, double ou triple clic, puis lecture via l'API d'accessibilité ; repli sur ⌘C avec restauration du presse-papiers (Chrome, apps Electron).
- Appel à Claude : `claude -p` sans réglages utilisateur, hooks, plugins, outils ni MCP, avec un prompt système dédié.
- Remplacement : collage (⌘V) dans l'app d'origine, puis restauration du presse-papiers.
- Le menu de la barre permet de désactiver la barre, de choisir le modèle (Haiku par défaut, Sonnet, Opus) et de lancer Plume à l'ouverture de session.
- Journal de diagnostic : `~/Library/Logs/Plume.log`.

## Contribuer

Compilation depuis les sources, publication et structure du code : voir [CONTRIBUTING.md](CONTRIBUTING.md).
