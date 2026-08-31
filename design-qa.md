# Codex Voice 3 — Design QA de l'app macOS

Date : 31 août 2026

## Sources comparées

- Référence validée : `Design/codex-voice-menu-reference.png`
- Rendu natif : `Design/codex-voice-menu-implemented.png`
- État comparé : connecté, voix active, volume à 80 %, lecture de « Améliorer la fusion »
- Rendu : bundle macOS réel, mode aperçu sans réseau et sans production audio

## Résultat visuel

| Niveau | Vérification | Résultat |
| --- | --- | --- |
| P0 | Contenu complet, lisible et non rogné | Passé |
| P0 | Halo visible et popin correctement ancrée | Passé |
| P1 | Hiérarchie conforme : identité, lecture, activation, volume, interruption | Passé |
| P1 | Contrôles natifs cohérents et états actifs immédiatement identifiables | Passé |
| P2 | Largeur compacte de 340 points, espacements et séparateurs réguliers | Passé |
| P2 | Fond sombre neutralisé pour rester sobre quel que soit l'arrière-plan | Passé |
| P2 | Titre de tâche tronqué proprement lorsqu'il dépasse l'espace disponible | Passé |
| P3 | Le halo réel est légèrement plus petit que l'illustration, dans la limite physique de la barre de menu macOS | Accepté |

L'implémentation ajoute uniquement deux affordances fonctionnelles discrètes à la référence : le rappel `⌥` sur l'action d'arrêt et un menu contextuel au clic droit permettant de quitter l'app.

## Validation fonctionnelle associée

- connexion WebSocket authentifiée et maintenue ouverte ;
- réception de changements d'état publiés par le service ;
- reconnexion automatique prévue après une coupure ;
- activation, volume et interruption reliés aux commandes réelles ;
- observation passive d'Option, sans consommer l'événement envoyé à Codex ;
- état désactivé conservé pendant les tests et aucune lecture audio produite.

final result: passed
