# Résultats du spike Codex App Server

Date : 31 août 2026
Version observée : `codex-cli 0.149.0-alpha.4.1`
Plateforme : macOS sur Apple Silicon

## Question

Un second client App Server peut-il observer en direct, sans les modifier, les tâches actuellement exécutées par l'app Codex afin d'alimenter Codex Voice V3 ?

## Résultat court

**Pas dans la topologie actuelle de l'app.**

Un App Server autonome peut lister les tâches persistées, récupérer leurs titres, relire leurs tours et distinguer les messages `commentary` des `final_answer`. Il ne peut toutefois pas appeler `thread/resume` sur une tâche active dans l'app : Codex refuse l'opération parce que cette tâche possède déjà un writer actif.

Cette protection empêche un second processus de s'abonner au flux live de la tâche. Le processus App Server utilisé par l'app communique par une connexion privée avec celle-ci et aucun socket de daemon partagé n'était disponible pendant l'expérience.

## Matrice de validation

| Capacité | Résultat | Observation |
|---|---|---|
| Lister les tâches | Validé | Les dix tâches demandées ont été retournées avec leur titre utilisateur. |
| Lire les tours persistés | Validé | Deux tâches ont fourni 85 tours lors du snapshot principal. |
| Scanner intégralement de gros historiques | À éviter | Une troisième lecture complète a dépassé le délai de 45 secondes. |
| Distinguer provisoire et final | Validé | 289 messages `commentary` et 84 `final_answer` ont été observés après la seconde lecture. |
| Reprendre après redémarrage sans doublon | Validé | 462 messages ont été reconnus comme déjà vus ; un seul message réellement nouveau a été ajouté. |
| S'abonner à une tâche inactive | Validé | Deux tâches ont été chargées, ont émis leur statut puis ont été désabonnées proprement. |
| S'abonner à la tâche active de l'app | Refusé par conception | `thread/resume` retourne `already has an active writer`. |
| Recevoir les deltas live de l'app depuis un second serveur | Non disponible | Impossible sans serveur réellement partagé entre l'app et la sonde. |
| Produire de l'audio | Hors périmètre | La sonde ne contient aucun composant audio. |

## Décision d'architecture

La V3 initiale utilisera deux sources complémentaires derrière un adaptateur unique :

1. **JSONL incrémental** pour détecter immédiatement les nouvelles lignes écrites par la tâche active et alimenter la lecture précoce.
2. **App Server snapshot** pour obtenir les titres, relire les tours structurés, confirmer les réponses finales et réparer l'état après une reconnexion.

Les événements sont corrélés par les identifiants Codex et une empreinte de contenu. L'orchestrateur vocal ne connaît pas la source utilisée.

Les snapshots seront ciblés par les signaux de fin détectés dans le JSONL. La production devra privilégier les lectures paginées et ne pas relire périodiquement la totalité des gros historiques.

Si une future version de Codex permet à l'app et à Codex Voice de se connecter au même daemon avec des abonnements multi-clients, l'implémentation live pourra passer à App Server sans changer le domaine vocal.

## Valeur du spike

Le spike a invalidé tôt l'hypothèse la plus séduisante — utiliser exclusivement App Server — tout en confirmant que son modèle sémantique reste très utile. Il évite donc de construire l'interface distante et l'orchestrateur sur un mécanisme d'abonnement incompatible avec l'app actuelle.

Les rapports détaillés contiennent des identifiants et métadonnées locales. Ils sont stockés dans `.probe/`, répertoire volontairement exclu du versioning.

## Validation de l'implémentation composite

La brique suivante a transformé la décision d'architecture en code exécutable. Sur une tâche réelle, le banc d'essai a normalisé 213 événements JSONL et 146 événements issus de `thread/read`, puis les a ramenés à 146 événements uniques : 144 confirmations App Server ont renforcé un événement déjà reçu sans recréer d'entrée de chronologie, une correction a enrichi le titre de la tâche et aucun diagnostic n'a été produit.

Cette validation confirme également deux détails du format persistant actuel :

- pour un message agent, `event_msg.item_completed` précède généralement `response_item` et les deux portent le même `itemId` ;
- pour un message utilisateur, les deux représentations n'ont pas le même identifiant. La V3 ignore donc la forme `response_item` et retient seulement `item_completed`, qui arrive immédiatement après avec le `turnId` explicite.

Le code et la procédure reproductible sont décrits dans `INGESTION-CORE.md`.
