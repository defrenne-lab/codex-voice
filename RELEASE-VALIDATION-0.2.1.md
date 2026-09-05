# Livraison v0.2.1 — deux retouches de la télécommande

## Périmètre et état

Version 0.2.1, build 12, en préparation le 5 septembre 2026.

- Stop discret à côté des flèches : commande d’interruption existante, sans
  fermeture de la popover ni désactivation globale de la voix.
- Recherche de mise à jour : libellé sans points de suspension ni icône dans
  la popover ; libellé identique dans le menu du clic droit.
- Aucun changement de code du service Mac mini, du protocole, du son de
  notification, des liens ou de l’installation/mise à jour Sparkle.
- Les retours d’usage de v0.2.0 sont conservés dans BATCH-VALIDATION.md.

## Vérifications

- Les 103 tests Swift passent sans échec ; les huit garde-fous de distribution
  passent. Résultat local dans `.build/release-0.2.1-tests.log`.
- Deux tests du modèle de vue couvrent l’arrêt, les appels répétés, la
  conservation de la conversation, de la navigation et de l’activation de la
  voix, et l’absence d’appel au gestionnaire de fermeture lié à Option.
- Le test du moteur de relecture vérifie que l’arrêt conserve la position et
  permet une navigation suivante explicite, sans reprise automatique.
- Rendu hors ligne de la popover inspecté : trois boutons discrets, compteur
  lisible, libellé de recherche simplifié. Ce rendu utilise un modèle isolé
  sans SSH ni audio ; la version du bandeau provient du lanceur XCTest et
  n’est pas une preuve du numéro de version du bundle distribué.
- Signature, notarisation, catalogue signé et téléchargement public : à valider
  sur les artefacts finaux avant annonce de disponibilité.

## Test utilisateur après publication

1. Depuis la v0.2.0 installée dans Applications, rechercher les mises à jour.
2. Vérifier que v0.2.1 est proposée ; confirmer installation et relancement.
3. Vérifier v0.2.1 et la connexion conservée au Mac mini.
4. Relancer un bloc d’historique, cliquer sur le petit Stop : la lecture cesse,
   la popover reste ouverte, la conversation et la position sont conservées.
5. Naviguer à nouveau avec les flèches ; vérifier aussi qu’Option conserve son
   comportement habituel et que le bouton de recherche a son nouveau libellé.

Le remplacement et le relancement réels sur le MacBook restent un test
utilisateur ; ils ne sont pas déclarés validés par les tests isolés.
