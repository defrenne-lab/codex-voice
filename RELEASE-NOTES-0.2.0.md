# Codex Voice 3 v0.2.0

Une seule version pour mieux travailler avec plusieurs tâches Codex, retrouver
les passages utiles et simplifier les prochaines mises à jour.

## Conversations et historique

- Cliquez sur le nom de la tâche principale pour en choisir une autre, sans
  envoyer de message ni interrompre le travail de l’agent.
- Deux petites flèches permettent de réécouter les paragraphes de la tâche
  sélectionnée, dans la limite de ses cinq derniers messages.
- Les tâches annexes restent silencieuses pendant la lecture principale.
  Leurs réponses finales donnent lieu à une notification courte : son doux,
  trois premiers mots du titre, puis une phrase extraite localement.
- Les notifications attendent dix secondes après la lecture principale et
  sont espacées de deux secondes. Une seule pression sur Option abandonne
  toute la série ; aucune reprise automatique.
- Les blocs de code et tableaux sont signalés brièvement, sans être dictés.
  Aucun texte n’est envoyé à un service de résumé externe.

## Fiabilité et interface

- Le retour d’un ancien journal ne déclenche plus sa relecture intégrale.
  L’ingestion et la mémoire récente sont bornées pour limiter la charge CPU.
- Le traitement reprend après une ligne excessive ou un fichier déplacé lors
  d’un archivage, sans bloquer l’ensemble des tâches.
- Pastille haut-parleur agrandie et fond translucide natif ; fond opaque
  conservé lorsque Réduire la transparence est activé dans macOS.

## Installation et mises à jour

- Première version distribuée avec signature Developer ID et notarisation Apple.
- **Rechercher une mise à jour…** utilise Sparkle et GitHub pour télécharger,
  vérifier, remplacer et relancer l’app après confirmation. Aucune recherche
  automatique, aucune installation silencieuse.
- Le DMG et le catalogue de mises à jour sont signés. La vérification intervient
  avant l’extraction et refuse un catalogue ou un téléchargement altéré.

**Pour passer de v0.1.x à cette version, une installation manuelle du DMG reste
nécessaire.** Ouvrez l’app dans le DMG et choisissez Installer et remplacer,
puis utilisez la copie dans Applications. Les prochaines versions pourront être
installées avec le bouton de mise à jour. macOS peut demander une nouvelle
autorisation pour la touche Option lors de ce changement de signature.

Le service Mac mini **et** le contrôleur MacBook doivent être mis à jour pour
les nouvelles fonctions. Sparkle met à jour uniquement le contrôleur MacBook.
Les réglages, le dictionnaire, le jeton et la configuration SSH sont conservés.

Application pour **Mac Apple Silicon, macOS 13 ou ultérieur**. La recette d’écoute
et de transparence sur le MacBook est à effectuer après installation.
