# Sonde Codex App Server

## Objectif

`codex-voice-probe` vérifie si Codex Voice V3 peut utiliser App Server comme source sémantique pour les tâches, les tours et les messages de Codex.

La sonde :

- liste les tâches récentes et leurs titres ;
- relit leurs tours sans les reprendre dans l'interface ;
- classe les messages `commentary`, `final_answer` ou sans phase ;
- conserve un checkpoint ne contenant que des identifiants et empreintes afin de mesurer la déduplication après redémarrage ;
- peut s'abonner à des tâches et journaliser les événements en direct ;
- ne contient aucun moteur audio et ne peut donc produire aucun son.

Elle n'envoie jamais `turn/start`, `turn/steer`, `thread/name/set`, archivage, suppression ou modification de contenu. Le mode `watch` utilise seulement `thread/resume` pour s'abonner puis `thread/unsubscribe` avant de quitter. App Server peut néanmoins réparer son propre index SQLite lors d'une lecture de l'historique ; cela ne modifie pas les messages des tâches.

## Compiler et tester

```bash
swift test
swift build
```

## Snapshot sans abonnement

```bash
swift run codex-voice-probe snapshot \
  --output .probe/runs/snapshot.json
```

La première exécution considère les messages retrouvés comme nouveaux. En relançant exactement la même commande, ils doivent apparaître comme déjà connus.

## Écoute de deux tâches

```bash
swift run codex-voice-probe watch \
  --subscribe-recent 2 \
  --watch-seconds 30 \
  --output .probe/runs/watch.json
```

Par défaut, aucun texte n'est imprimé : seules les tailles, phases et identités sont journalisées. `--include-text` ajoute des extraits courts pour une inspection manuelle locale.

Une tâche précise peut être suivie avec `--thread ID`. L'option peut être répétée.

## Transports

### `auto`

Mode par défaut. La sonde utilise le daemon partagé si son socket de contrôle existe, sinon elle lance un App Server autonome en stdio.

### `standalone`

```bash
swift run codex-voice-probe snapshot --transport standalone
```

Ce mode sait lire les tâches persistées. Il permet de valider l'historique, les titres, les blocs et la déduplication. Il ne faut pas supposer qu'il recevra les événements produits par un autre processus App Server : un résultat silencieux en `watch` est précisément une limite à mesurer.

### `daemon`

```bash
swift run codex-voice-probe watch --transport daemon
```

La sonde passe par `codex app-server proxy` et le socket :

```text
~/.codex/app-server-control/app-server-control.sock
```

Ce mode est le test décisif pour les événements multi-clients. L'app Codex et la sonde doivent parler au même daemon. La sonde ne démarre, n'arrête et ne configure jamais ce daemon elle-même.

## Critères du spike

App Server peut devenir la source principale de la V3 si l'expérience réelle confirme :

1. les tâches de l'app Codex sont listées avec leur titre ;
2. deux tâches peuvent être suivies sans altérer leur contenu ;
3. les événements `item/agentMessage/delta`, `item/completed` et `turn/completed` sont reçus ;
4. une seconde exécution reconstruit l'historique sans redéclarer les mêmes messages comme nouveaux ;
5. les réponses finales sont reconnaissables malgré les messages dont la phase est absente.

Si le point 2 ou 3 échoue avec un daemon véritablement partagé, l'ingestion JSONL reste la source de repli prévue par l'architecture V3.

## Résultat sur le Mac mini

Le résultat daté et publiable est consigné dans [`APP-SERVER-SPIKE-RESULTS.md`](APP-SERVER-SPIKE-RESULTS.md).

En résumé, les snapshots App Server sont exploitables, mais la tâche active de l'app ne peut pas être reprise par un second serveur : Codex retourne `already has an active writer`. L'architecture V3 initiale utilise donc JSONL pour le flux live et App Server pour les titres, l'historique structuré et la réconciliation.
