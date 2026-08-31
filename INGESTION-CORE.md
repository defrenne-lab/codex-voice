# Codex Voice V3 — cœur d'ingestion composite

Date de validation : 31 août 2026

## Résultat

La première brique de production de la V3 est opérationnelle. Le package Swift expose maintenant un module `CodexVoiceCore` indépendant de l'audio et de l'interface, ainsi qu'un banc d'essai `codex-voice-ingest`.

Le cœur combine deux sources :

- le JSONL fournit les événements à faible latence pendant que l'app Codex possède la tâche ;
- l'App Server relit en lecture seule les seules tâches observées afin de confirmer leur état structuré et leur titre.

Les deux sources produisent le même modèle interne. Un consommateur ne reçoit qu'une nouvelle entrée de chronologie ; une représentation plus fiable du même événement met à jour son état sans provoquer une seconde lecture.

## Composants

- `CodexEvent` définit les tâches, tours, messages utilisateur, messages agent et fins de tour avec `threadId`, `turnId` et `itemId`.
- `JSONLTranscriptEventSource` suit les fichiers par offset, conserve les lignes incomplètes, détecte une troncature ou un remplacement et ignore les sous-agents.
- `JSONLTranscriptNormalizer` comprend le format persistant observé avec Codex Desktop 0.149.
- `AppServerSnapshotReader` utilise uniquement `thread/list` et `thread/read`; il ne tente jamais de reprendre la tâche ni d'en devenir writer.
- `AppServerSnapshotEventSource` transforme les réponses structurées en événements du domaine.
- `CompositeCodexEventSource` classe chaque observation comme insertion, confirmation, correction, doublon ou donnée moins fiable à ignorer.

## Règles importantes

### Pas de relecture au démarrage

En fonctionnement normal, la source démarre à la fin des fichiers existants. Elle lit l'en-tête nécessaire à l'identité de la tâche, puis une fenêtre de fin bornée pour reconstruire le tour ouvert sans reparcourir les gros historiques. Elle ne livre ensuite que les nouvelles lignes.

Le mode `--from-beginning` appartient au banc d'essai et aux opérations de diagnostic.

### Déduplication des messages

Le journal courant écrit deux représentations d'un message agent terminé. Elles partagent le même `itemId`; la première crée l'événement et la seconde est absorbée.

Les deux représentations d'un message utilisateur ont actuellement des identifiants différents. Comme `item_completed` suit immédiatement et fournit explicitement le `turnId`, seule cette forme entre dans le domaine. Le texte de l'utilisateur n'est pas conservé par ce modèle.

### Réconciliation ciblée

Le banc d'essai transmet à l'App Server les identifiants effectivement découverts dans le JSONL. Il n'effectue pas de balayage régulier de tous les historiques, car certaines tâches volumineuses peuvent être lentes à relire.

### Autorité des sources

L'ordre de confiance est :

1. instantané App Server ;
2. `item_completed` et événements de cycle de vie JSONL ;
3. `response_item` JSONL utilisé seulement comme repli.

Une confirmation plus forte ne crée jamais une nouvelle entrée de chronologie. Une correction de contenu ou de métadonnée met l'état à jour sans demander une nouvelle prise de parole.

## Validation automatisée

La suite couvre désormais 40 tests au total, dont 11 pour l'ingestion :

- format JSONL actuel et double représentation ;
- confirmation App Server sans deuxième entrée de chronologie ;
- ligne partielle ;
- démarrage à la fin sans rattrapage audio ;
- reconstruction du tour courant depuis la fin d'un transcript volumineux ;
- troncature ou réécriture d'un fichier ;
- remplacement d'un journal suivi sans relecture historique en mode production ;
- exclusion des sous-agents ;
- représentation utilisateur non ambiguë et sans conservation du texte ;
- ciblage explicite d'une tâche dans un environnement réellement concurrent ;
- ordre chronologique des événements provenant de plusieurs fichiers.

Commande :

```shell
swift test
```

## Validation sur une tâche réelle

Commande générique :

```shell
swift run codex-voice-ingest \
  --from-beginning \
  --watch-seconds 0 \
  --thread <THREAD_ID> \
  --reconcile-app-server \
  --snapshot-limit 1
```

Résultat observé :

- 213 événements JSONL normalisés ;
- 146 événements App Server normalisés ;
- 146 événements uniques dans le composite ;
- 144 événements renforcés par l'App Server sans nouvelle entrée ;
- une correction de métadonnée correspondant au titre enrichi ;
- 68 doublons absorbés au total ;
- aucun diagnostic ;
- aucun texte de message affiché par le banc d'essai.

## Briques suivantes

L'orchestrateur minimal et le coordinateur audio local sont maintenant implémentés. Leur machine à états et leurs validations sont décrites dans `VOICE-ORCHESTRATOR.md` et `AUDIO-COORDINATOR.md`.
