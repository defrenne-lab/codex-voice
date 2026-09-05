# Livraison v0.2.1 — deux retouches de la télécommande

## Périmètre et état

**Version 0.2.1, build 12, publiée le 5 septembre 2026.**
[Release GitHub](https://github.com/defrenne-lab/codex-voice/releases/tag/v0.2.1).
Sources de l’application : `f19eb32cb6cce92a60678b4113b6e12c525e8051`.

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
- Signature Developer ID, notarisation Apple et agrafage validés. Soumission
  `1e2f03c3-711d-48e5-864c-1ea7645b2e10`, statut Accepted, aucun avertissement.
- DMG monté en lecture seule : v0.2.1/build 12 dans le bundle, signature
  récursive valide, application acceptée par Gatekeeper comme Notarized
  Developer ID. Image démontée sans lancer la copie.
- Catalogue Sparkle signé avec la clé existante et vérifié par la clé publique :
  build 12 proposé, build 11 conservé avec son URL d’origine ; aucun delta ni
  version de test. DMG final : 2 912 776 octets.
- [CI des sources](https://github.com/defrenne-lab/codex-voice/actions/runs/33961539647)
  verte : tests, garde-fous, skill, vérificateur public et compilation release.
- DMG et checksum téléchargés publiquement sans authentification : checksum
  valide et image identique octet pour octet à l’artefact final. Notarisation
  et signature Sparkle vérifiées sur cette copie téléchargée.
- Catalogue téléchargé à son URL publique exacte sur `main`, identique aux
  octets signés ; signatures du catalogue et du DMG public, version, build,
  longueur et URL validés ensemble avec le vérificateur à clé publique.
- Aucun remplacement ni redémarrage du service Mac mini pendant cette livraison.
  Les sources du service sont inchangées par rapport au commit de v0.2.0.

SHA-256 final :
`e01750429a7bf875e8e2e241a40e37969e1c20d01212e02cc5941d714199b6bc`.

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
