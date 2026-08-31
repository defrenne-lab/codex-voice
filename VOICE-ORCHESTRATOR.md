# Codex Voice V3 — orchestrateur vocal minimal

Date de validation : 31 août 2026

## Résultat

`VoiceOrchestrator` transforme désormais la chronologie technique de Codex en décisions produit, sans dépendre d'un moteur audio.

La conversation principale n'est pas seulement un `threadId`. Elle est définie par le couple `threadId + turnId` du dernier message utilisateur observé en direct. Cette précision empêche un ancien tour de la même tâche de reprendre la parole lorsqu'un événement arrive en retard.

## Règles implémentées

1. Un message utilisateur live sélectionne sa tâche et son tour comme conversation principale.
2. Un élément `commentary` ne demande une lecture que s'il appartient exactement à cette conversation principale.
3. Un `final_answer` de la conversation principale demande une lecture une seule fois.
4. Une réponse finale parallèle reste silencieuse jusqu'à `turnCompleted`, puis devient une réponse en attente.
5. Une phase absente n'est jamais lue immédiatement. À la fin du tour, le dernier message sans phase sert de réponse finale prudente si aucun `final_answer` n'existe.
6. Un tour parallèle interrompu ou en échec ne crée pas de notification de réponse.
7. Envoyer un nouveau message dans une tâche supprime ses anciennes notifications parallèles en attente devenues obsolètes.
8. Un instantané App Server enrichit les titres, textes et statuts, mais ne peut jamais sélectionner la conversation principale ni provoquer une lecture historique.
9. Une confirmation, une correction ou une deuxième représentation du même message ne déclenche jamais une seconde lecture.

Ces règles s'appuient sur le contrat documenté de Codex : `agentMessage.phase` est facultatif et vaut, lorsqu'il est présent, `commentary` ou `final_answer`; `item/completed` est l'état faisant foi; `turn/completed` fournit le statut final du tour. Voir la [documentation officielle Codex App Server](https://learn.chatgpt.com/docs/app-server).

## Effets produits

L'orchestrateur ne parle jamais directement. Il publie quatre intentions typées que le coordinateur audio peut désormais consommer :

- `mainConversationChanged` : la conversation vocale courante a changé ;
- `speechRequested` : un message de la conversation principale est éligible à la lecture ;
- `parallelResponseReady` : une réponse parallèle terminée peut entrer dans le futur planificateur de notifications ;
- `pendingResponsesCleared` : une ancienne notification doit être retirée parce que l'utilisateur a repris cette tâche.

Chaque demande de lecture conserve le titre connu, le texte et les trois identifiants `threadId`, `turnId`, `itemId`. Le prochain moteur pourra donc interrompre, journaliser ou rejouer une unité sans perdre son rattachement à Codex.

## État observable

Un instantané léger expose :

- la conversation principale courante ;
- le titre et le dernier tour utilisateur de chaque tâche ;
- les réponses parallèles en attente et leur heure de disponibilité.

Le contenu d'une réponse en attente est résolu depuis l'état canonique. Une correction App Server du titre ou du message enrichit donc automatiquement la notification future sans en créer une nouvelle.

## Ordre multi-tâches

`JSONLTranscriptEventSource` ordonne maintenant les événements provenant de plusieurs fichiers par leur horodatage Codex avant de les transmettre. L'ordre de parcours du système de fichiers ne décide plus arbitrairement quelle tâche est principale.

L'orchestrateur conserve également l'heure de la dernière sélection : une ligne plus ancienne découverte tardivement dans un autre fichier ne peut pas reprendre la conversation principale. Les tests couvrent ces deux niveaux de protection.

## Validation automatisée

La suite compte 40 tests :

- 11 tests d'ingestion et d'ordre multi-fichiers ;
- 10 scénarios d'orchestration ;
- 8 scénarios du coordinateur audio ;
- 6 scénarios du service de contrôle ;
- 2 scénarios de stockage sécurisé du jeton ;
- 3 tests de la sonde App Server initiale.

Les scénarios d'orchestration couvrent notamment le changement de tâche principale, les commentaires d'un ancien tour, les réponses parallèles, les phases absentes, les échecs, les corrections de titre et le cas où un instantané a vu un événement avant le JSONL live.

## Validation sur des données réelles

### Une tâche avec réconciliation App Server

- 226 observations JSONL ;
- 154 observations App Server ;
- 154 événements uniques ;
- 49 commentaires et 24 réponses finales éligibles à la lecture ;
- aucun doublon de lecture et aucun diagnostic.

### Deux tâches réellement entrelacées

- 62 éléments `commentary` observés, dont 56 seulement ont été déclarés lisibles ;
- 6 commentaires parallèles sont donc restés silencieux ;
- 27 réponses finales observées ;
- 26 réponses principales déclarées lisibles ;
- une réponse parallèle transformée en attente à la fin de son tour ;
- cette attente a ensuite été supprimée naturellement quand l'utilisateur a envoyé un nouveau message dans cette tâche.

Aucun son n'a été produit pendant ces validations et le banc d'essai n'affiche pas le texte des messages.

## Suite de l'architecture

`speechRequested` reste une décision d'éligibilité, mais `VoiceAudioCoordinator` sait maintenant la transformer en lecture macOS non préemptive, interruptible et persistante. Le contrat audio figure dans `AUDIO-COORDINATOR.md`; son contrôle WebSocket authentifié est décrit dans `REMOTE-CONTROL.md`. La prochaine étape est l'app menu-bar MacBook et sa touche Option.
