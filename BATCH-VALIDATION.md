# Recette du lot regroupé

## Statut

**v0.2.0 / build 11 livrée le 5 septembre 2026.**

- [Version GitHub](https://github.com/defrenne-lab/codex-voice/releases/tag/v0.2.0),
  sources de l’application au commit `087a828`.
- 101 tests automatisés passent, sans échec, et les huit garde-fous de
  distribution passent. La [CI de la version](https://github.com/defrenne-lab/codex-voice/actions/runs/33959251026)
  est verte. Le journal local est `.build/combined-lot-tests.log`.
- Developer ID, Hardened Runtime et signatures imbriquées vérifiés.
  Notarisation Apple acceptée sans anomalie, soumission
  `f7fa2328-5078-421a-9205-02a01b00270b`. Ticket agrafé et vérifié.
- DMG et application contenus acceptés par Gatekeeper comme Notarized
  Developer ID. Versions et architecture arm64 vérifiées dans le DMG monté,
  sans lancer une autre copie de l’app.
- Téléchargement public GitHub effectué sans authentification : identique
  octet pour octet au DMG final, checksum vérifié, signature Sparkle valide
  et ticket de notarisation valide après téléchargement.
- Catalogue signé généré avec l’outil Sparkle officiel, limité à la vraie
  version 0.2.0 ; aucun binaire de test annoncé. Signatures du catalogue et
  de l’archive vérifiées avec la seule clé publique. Catalogue altéré refusé.
- Service Mac mini remplacé et actif ; binaires comparés à la compilation
  release. Ancienne version sauvegardée dans le dossier privé de l’application.
  Réglages, dictionnaire, jeton et LaunchAgent vérifiés inchangés.

SHA-256 du DMG final :
`a25dda0f584cdf74f8c5838705f1a7be36c0139c1fdd1cc7fddd4be7aa40ed05`

Le premier redémarrage du service a rencontré un délai de libération launchd ;
le retour arrière a restauré l’ancienne version, puis une reprise bornée a
réussi. Aucun changement de configuration ni de droits n’a été nécessaire.

**Reste côté utilisateur :** une installation manuelle sur le MacBook pour
amorcer Sparkle, puis la recette d’usage ci-dessous. Les écoutes, Option et le
flou réel sur ce Mac ne sont pas présentés comme validés automatiquement.

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

## Procédure de livraison regroupée

1. Finaliser la validation du lot ; augmenter les deux
   champs de version sans remplacer un artefact déjà publié.
2. Tester/compiler le service et l’application, préparer le DMG Developer ID,
   le faire notarier, l’agrafer et vérifier le résultat. Ne pas distribuer les
   copies de test ni le build d’aperçu.
3. Préparer le catalogue signé puis publier uniquement après accord, en suivant
   UPDATES.md. Le bouton de mise à jour ne peut pas fonctionner contre un
   catalogue public qui n’a pas encore été publié.
4. Mettre à jour le service Mac mini, avec sauvegarde du binaire précédent et
   conservation de ses réglages/dictionnaire/jeton. Cette opération n’est pas
   exécutée par Sparkle ; elle a été effectuée lors de la livraison 0.2.0.
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
