# Recette du lot regroupé

## Statut

Sources implémentées, non publiées. Le 5 septembre 2026 : 101 tests automatisés
passent, sans échec, et les huit garde-fous de distribution passent. Le journal
de validation local est `.build/combined-lot-tests.log`. La livraison du lot a été
autorisée le 5 septembre : le candidat est v0.2.0/build 11, distinct de tous les
artefacts déjà publiés. Signature, notarisation et publication restent des
contrôles obligatoires avant de l’annoncer comme disponible.

Le test Sparkle isolé est terminé, voir UPDATES.md. La copie d’aperçu du lot
utilise un identifiant distinct et `CODEX_VOICE_PREVIEW=1` : aucune connexion,
aucun jeton, pas de lecture de `.env`, pas d’observation de la touche Option.
Le contrôle UI a dépassé son délai le 5 septembre ; la copie a été arrêtée.
Le rendu hors ligne du sélecteur et des flèches a été inspecté. Cela ne valide
pas le flou natif sur un véritable arrière-plan ni le son sur les haut-parleurs.

## Contrôles automatisés

- Journaux : lecture par blocs de 256 Kio/fichier, lignes limitées à 2 Mio,
  parcours en avant et compactage unique ; reprise après ligne excessive.
- Retour d’un ancien journal : au plus en-tête 64 Kio + fin 2 Mio, pas de
  rattrapage vocal. Les observations historiques sont séparées des événements
  nouveaux. Les fichiers disparus pendant un archivage ne font pas tomber
  toute la boucle d’ingestion.
- Historique : cinq messages par tâche, 32 tâches, 128 blocs et 65 536 caractères
  par message. Correction d’un message en place ; le final remplace les
  paragraphes de progression du même tour. Aucun texte de message dans les
  métadonnées envoyées au contrôleur distant.
- Sélection : aucun message envoyé à Codex ; seuls les contenus suivants de
  la tâche choisie deviennent prioritaires. Un nouveau message utilisateur
  reprend la sélection automatique et interrompt le contexte parlé précédent.
  Une tâche dont le journal ne contient plus de contexte de tour dans la fin
  bornée reste sélectionnable grâce à son en-tête ; son prochain message vivant
  rattache le tour à la sélection. Les entrées de l’index sans journal observé
  ne remplissent pas le menu de tâches anciennes.
- Flèches : un bloc par action, bornes désactivées, arrêt explicite sans reprise.
- Notifications : final uniquement, jamais de changement de tâche principale,
  dix secondes après chaque lecture principale, deux secondes entre notifications.
  Une reprise de parole principale pendant une pause rétablit les dix secondes.
  Une interruption unique, même entre deux notifications, supprime toute la rafale.
- Authentification, commandes répétées, compatibilité des champs optionnels,
  vérification des signatures et tests de distribution restent dans la suite.

## Choix de produit retenus et validation sonore

L’utilisateur a confirmé le 5 septembre 2026 l’extraction locale pour commencer.
Le résumé est une phrase extraite de la réponse, limitée à 30 mots et
180 caractères, précédée des trois premiers mots du titre. Ce n’est pas une
reformulation par IA ; aucun service externe ni clé API n’est nécessaire.
Le signal doux provisoire est le son macOS Glass à volume réduit ; il est
interrompu immédiatement avec la lecture et reste à écouter lors de la recette.

## Préparation d’une seule version

1. Finaliser la validation du lot ; augmenter les deux
   champs de version sans remplacer un artefact déjà publié.
2. Tester/compiler le service et l’application, préparer le DMG Developer ID,
   le faire notarier, l’agrafer et vérifier le résultat. Ne pas distribuer les
   copies de test ni le build d’aperçu.
3. Préparer le catalogue signé puis publier uniquement après accord, en suivant
   UPDATES.md. Le bouton de mise à jour ne peut pas fonctionner contre un
   catalogue public qui n’a pas encore été publié.
4. Mettre à jour une seule fois le service Mac mini, avec sauvegarde du binaire
   précédent et conservation de ses réglages/dictionnaire/jeton. Cette opération
   n’est pas exécutée par Sparkle et n’a pas été faite pendant le développement.
5. Faire une seule installation de l’application sur le MacBook, puis la recette
   ci-dessous avec l’utilisateur. Ne pas recréer les clés SSH ni les mots de passe.

## Recette utilisateur finale, sur le MacBook

- Vérifier le numéro de version, la connexion et les voix/réglages conservés.
- Vérifier la taille de la pastille et le fond translucide sur un arrière-plan
  coloré ; vérifier également la lisibilité avec Réduire la transparence.
- Sélectionner une tâche dont l’agent travaille encore : aucun message envoyé,
  aucun arrêt de l’agent ; sa réponse suivante est lue.
- Réécouter les blocs avec les flèches, y compris une tâche restée silencieuse ;
  arrêter avec Option et vérifier l’absence de reprise automatique.
- Faire terminer deux tâches annexes pendant une lecture principale : attendre
  dix secondes après sa fin, puis entendre les notifications espacées ; une
  pression sur Option doit supprimer toute la suite, même pendant une pause.
- Désactiver la voix, produire des réponses, réactiver : aucun ancien lot rejoué.
- Vérifier volume système, vitesse, dictionnaire et partage d’écran.
- Vérifier Rechercher une mise à jour avec le vrai catalogue HTTPS publié.

La recette n’exige pas de réinstaller My Coaches ou Real Score ni de changer
leurs certificats, réglages ou profils.
