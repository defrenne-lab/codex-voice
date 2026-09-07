# Livraison v0.3.0 — lecture structurée et historique à deux niveaux

## Périmètre

**Version 0.3.0, build 13, préparée le 7 septembre 2026.**

- Lecture ligne par ligne des blocs encadrés de code ou de texte brut.
- Lecture ligne par ligne des tableaux Markdown, sans leur séparateur syntaxique.
- Résumés annexes toujours limités au texte courant non technique.
- Navigation distincte par réponse puis par bloc dans la réponse sélectionnée.
- Aperçu de réponse authentifié limité aux huit premiers mots.
- Compatibilité transitoire conservée avec les anciennes commandes de navigation.

## Vérifications automatisées et distribution

- Les 106 tests Swift passent sans échec sur les sources versionnées.
- Les huit garde-fous de distribution passent.
- La construction signée, la notarisation, la publication publique, la CI et
  le déploiement du service Mac mini restent à consigner ci-dessous.

## Recette utilisateur après publication

1. Mettre à jour le contrôleur depuis **Rechercher une mise à jour** et vérifier
   l’affichage de v0.3.0.
2. Choisir une conversation, puis vérifier que la ligne « Réponse » relit une
   réponse depuis son début et que la ligne « Bloc » reste dans cette réponse.
3. Vérifier qu’un bloc de code lisible est dicté ligne par ligne.
4. Vérifier qu’un tableau est dicté ligne par ligne, sans la ligne de tirets.
5. Vérifier que Stop interrompt la réécoute sans fermer la popover.
