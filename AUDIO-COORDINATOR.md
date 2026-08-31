# Codex Voice V3 — coordinateur audio local

Date de validation : 31 août 2026

## Résultat

La première boucle audio de production est opérationnelle sur macOS. `VoiceAudioCoordinator` reçoit les décisions de `VoiceOrchestrator`, les transforme en unités de parole non préemptives et pilote un adaptateur `AVSpeechSynthesizer` séparé du cœur métier.

Un exécutable local, `codex-voice-local`, assemble maintenant ingestion JSONL, déduplication, orchestration et TTS macOS. Il démarre à la fin des journaux existants et une nouvelle installation conserve volontairement la voix désactivée : lancer ou tester le programme ne peut donc pas provoquer une relecture historique inattendue.

## Contrat audio implémenté

1. Une seule unité est lue à la fois ; les suivantes attendent en FIFO et ne préemptent jamais la lecture courante.
2. L'interruption utilisateur abandonne immédiatement la lecture et toute sa file. Tous les tours concernés sont marqués comme rejetés pour la durée du processus : aucun fragment du lot ne repart automatiquement.
3. Désactiver la voix ou activer la sourdine arrête immédiatement la lecture et vide la file.
4. Une réactivation ne rejoue aucun arriéré. Seules de nouvelles décisions de l'orchestrateur peuvent être acceptées.
5. Une unité déjà acceptée ne peut être lue deux fois, même si sa représentation technique réapparaît.
6. Une fin tardive envoyée par le pilote après une interruption est ignorée et ne peut pas faire avancer une ancienne file.
7. Le volume, la vitesse, la voix choisie, l'activation et la sourdine sont persistants.

L'unité conserve les identifiants de tâche, de tour et de message. Le groupement d'interruption se fait au niveau du tour, ce qui prépare l'abandon atomique des futurs lots de notifications parallèles.

## Adaptateur macOS

`MacOSSpeechDriver` encapsule `AVSpeechSynthesizer`. Il applique un volume propre à chaque énoncé, une voix explicite lorsqu'elle est choisie et, sinon, la voix française du système.

La V2 a été consultée uniquement pour réutiliser les réglages éprouvés sur plusieurs mois : vitesse par défaut `0.48`, hauteur `1.0`, repli `fr-FR` et arrêt immédiat. Son comportement de remplacement automatique de la lecture active n'a pas été repris, car il contredit la règle V3 de non-préemption.

Les voix françaises installées peuvent être inspectées sans produire de son :

```shell
swift run codex-voice-local --list-voices
```

## Runtime local sûr

Le runtime peut mémoriser les réglages tout en restant borné pour les essais :

```shell
swift run codex-voice-local --disable-voice --watch-seconds 0
swift run codex-voice-local --disable-voice --volume 0.6 --rate 0.48 --watch-seconds 0
```

L'activation explicite existe avec `--enable-voice`; `--forever` transforme ensuite le banc local en processus continu. Ce runtime n'est pas encore le service final : il ne possède ni serveur de contrôle distant ni branchement sur la touche Option.

Le démarrage à la fin ne reparcourt plus l'intégralité des gros historiques. Pour chacun des seize fichiers récents suivis par défaut, la source lit l'en-tête nécessaire à l'identité de la tâche et au plus les deux derniers mébioctets pour reconstruire le tour courant. Sur les journaux réels présents au moment du test, l'exécutable Release, désactivé et sans observation, a terminé en `0,63 s`, avec zéro événement, zéro demande audio et zéro diagnostic.

## Validation

La suite compte maintenant 42 tests, dont 8 scénarios spécifiques au coordinateur audio et 11 scénarios d'ingestion. Elle couvre la file non préemptive, l'interruption atomique, la désactivation, la sourdine, la persistance abstraite des réglages, la déduplication, les callbacks tardifs, le démarrage à la fin d'un transcript volumineux et le remplacement sûr d'un journal déjà suivi.

Le pilote macOS réel a été chargé et a correctement découvert les voix françaises installées. Aucun son n'a été produit pendant cette validation : le chemin de lecture réelle reste à essayer volontairement une fois le contrôle d'interruption disponible.

La validation réelle a ensuite révélé des microcoupures précisément corrélées à des erreurs Core Audio `skipping cycle due to overload`. Le moteur était identique à celui de la V2, mais son LaunchAgent V3 avait été classé `Background`. La classification est désormais `Interactive`, ce qui correspond à la contrainte de réactivité de la lecture et évite la limitation de ressources appliquée aux tâches d'arrière-plan.

## Prochaine brique

Le plan de contrôle distant et son client de diagnostic sont désormais décrits dans `REMOTE-CONTROL.md`. La prochaine étape est l'app menu-bar MacBook et le raccordement de la touche Option, afin de restaurer le push-to-talk complet avant d'ajouter la surface iPad.
