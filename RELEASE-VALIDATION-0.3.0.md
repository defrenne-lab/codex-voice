# Livraison v0.3.0 — lecture structurée et historique à deux niveaux

## Périmètre

**Version 0.3.0, build 13, publiée le 7 septembre 2026.**
[Release GitHub](https://github.com/defrenne-lab/codex-voice/releases/tag/v0.3.0).
Sources de l’application : `b1d44eda7c332d2fc47fa2044105062a2d3f1221`.

- Lecture ligne par ligne des blocs encadrés de code ou de texte brut.
- Lecture ligne par ligne des tableaux Markdown, sans leur séparateur syntaxique.
- Résumés annexes toujours limités au texte courant non technique.
- Navigation distincte par réponse puis par bloc dans la réponse sélectionnée.
- Aperçu de réponse authentifié limité aux huit premiers mots.
- Compatibilité transitoire conservée avec les anciennes commandes de navigation.

## Vérifications automatisées et distribution

- Les 106 tests Swift passent sans échec sur les sources versionnées.
- Les huit garde-fous de distribution passent.
- La CI des sources et celle du catalogue final sont vertes :
  [candidat](https://github.com/defrenne-lab/codex-voice/actions/runs/34099887704),
  [catalogue publié](https://github.com/defrenne-lab/codex-voice/actions/runs/34100240526).
- L’application et le DMG sont signés avec le certificat Developer ID dédié.
  La soumission Apple `c6024275-89ee-4bdb-b0ee-a9a0b8268883` est acceptée,
  sans avertissement ; le ticket est agrafé et Gatekeeper reconnaît le DMG
  comme `Notarized Developer ID`.
- Le catalogue Sparkle signé propose v0.3.0/build 13 et conserve v0.2.1/build 12
  et v0.2.0/build 11 sans delta. Sa signature, celle du DMG, la version, le
  build, l’URL et la longueur de 2 941 922 octets sont validés ensemble.
- Le DMG, son checksum et le catalogue ont été retéléchargés publiquement sans
  authentification. Le DMG public est identique octet pour octet au candidat,
  le catalogue public est identique au fichier signé, et les contrôles
  checksum, Sparkle, signature Apple, agrafage et Gatekeeper passent.
- SHA-256 final :
  `53486792c2c6b7c6ad95516a38a3ed1d64cd0fe9b58e8cbd419113252cbe6be5`.

## Déploiement du service Mac mini

- Une sauvegarde privée des anciens binaires, du LaunchAgent, des réglages, du
  dictionnaire et du jeton a été créée avant remplacement.
- Les binaires release installés sont identiques octet pour octet à ceux du
  candidat ; le LaunchAgent `lab.defrenne.codexvoice3.local` est actif.
- Le jeton, le dictionnaire et les réglages audio sont identiques avant/après.
  La vérification par la skill confirme : voix active, Thomas Enhanced,
  vitesse 0,53, volume système inchangé à 0,39295784, aucune lecture ni file en
  attente après redémarrage.
- Le catalogue final est versionné dans le commit
  `3ba201c37657e05647046292aef7501820e4781e`.

## Recette utilisateur après publication

1. Mettre à jour le contrôleur depuis **Rechercher une mise à jour** et vérifier
   l’affichage de v0.3.0.
2. Choisir une conversation, puis vérifier que la ligne « Réponse » relit une
   réponse depuis son début et que la ligne « Bloc » reste dans cette réponse.
3. Vérifier qu’un bloc de code lisible est dicté ligne par ligne.
4. Vérifier qu’un tableau est dicté ligne par ligne, sans la ligne de tirets.
5. Vérifier que Stop interrompt la réécoute sans fermer la popover.
