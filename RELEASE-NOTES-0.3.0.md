# Codex Voice 3 v0.3.0

Cette version rend les réponses techniques plus compréhensibles à l’oral et
facilite le retour au bon endroit dans une conversation longue.

## Lecture structurée

- Les blocs de code et de texte brut sont désormais lus ligne par ligne, au
  lieu d’être entièrement sautés.
- Les tableaux Markdown sont lus ligne par ligne, avec une séparation audible
  entre les cellules ; leur ligne de mise en forme est ignorée.
- Les notifications des conversations annexes restent courtes et ne choisissent
  jamais une ligne de code ou de tableau comme résumé.

## Historique à deux niveaux

- Une première ligne de flèches navigue parmi les cinq dernières réponses de
  la conversation et relit la réponse choisie depuis son début.
- Une seconde ligne navigue bloc par bloc à l’intérieur de cette réponse.
- Un aperçu court permet d’identifier la réponse sélectionnée. Il reste local,
  borné aux huit premiers mots et n’est envoyé qu’au contrôleur authentifié.
- Le bouton Stop coupe toujours la réécoute sans fermer la popover ni perdre la
  sélection.

Le service du Mac mini et le contrôleur du MacBook doivent tous deux passer à
cette version. Le service est déployé séparément ; sur le MacBook, utilisez
**Rechercher une mise à jour** dans Codex Voice 3. Les réglages, la voix, le
volume, le dictionnaire, le jeton de contrôle et la configuration SSH sont
conservés.
