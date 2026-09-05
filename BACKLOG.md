# Backlog

## Prochain lot — regroupé, implémentation en cours

Le 5 septembre 2026, l’utilisateur a demandé de regrouper toutes ces
modifications et de ne faire qu’une installation/recette à la fin. La préparation
d’une version séparée pour Sparkle est donc suspendue. Aucun service réel ni
application installée n’a été remplacé pendant ce lot.

État des sources : correction du lecteur borné, mémoire de cinq messages,
sélection distante, flèches, notifications temporisées, pastille agrandie et
fond natif translucide intégrés. Les 101 tests automatisés passent, ainsi que
les huit garde-fous de distribution ; le rendu hors ligne a été inspecté.
Le contrôle natif automatisé a dépassé son délai et sa copie
d’aperçu a été fermée. La transparence en situation réelle reste à vérifier.

Le 5 septembre 2026, l’utilisateur a confirmé l’extraction locale pour cette
première version des notifications : une courte phrase issue de la réponse,
pas une synthèse IA reformulée. Aucun service externe ni clé API n’est nécessaire.
La fabrication/notarisation du DMG final, le déploiement coordonné du service
Mac mini, la première installation MacBook et la publication restent à faire.

### Fiabilité

- Corriger le lecteur de journaux : suivre les nouveaux contenus sans relire intégralement un ancien journal lorsqu’il revient parmi les fichiers surveillés. Retrouver le contexte par une lecture limitée de la fin du fichier, sans rattrapage audio historique.
- Traiter les nouvelles données par portions bornées, avec un parcours linéaire qui évite les recopies répétées du tampon et limite la consommation mémoire ainsi que le temps de traitement par passage.

### Interface

- Agrandir la pastille haut-parleur pour qu’elle soit presque aussi grosse que les icônes classiques de la barre de menu, en augmentant ensemble le rond bleu et le haut-parleur blanc. À intégrer au prochain lot de modifications, une fois son périmètre défini ensemble.
- Transparence de la popover confirmée : rechercher un effet graphique soigné et perceptible. Piste proposée : fond translucide façon verre dépoli, avec un flou laissant deviner les couleurs de l’arrière-plan et une bonne lisibilité du texte et des contrôles. À intégrer au même lot, une fois son périmètre défini ensemble.
- Sélecteur de conversation principale validé : rendre le titre cliquable dans la popover pour ouvrir un menu des tâches récentes et choisir celle qui a la parole. La sélection ne doit envoyer aucun message à Codex ni interrompre le travail de l’agent ; les prochains messages de la tâche choisie deviennent éligibles à la lecture. Envoyer ensuite un message dans une tâche la désigne à nouveau automatiquement comme principale.

### Historique audio

- Deux petites flèches précédent/suivant, discrètes, sous le sélecteur de conversation. Navigation par bloc avec lecture du bloc choisi ; pendant une lecture, revenir au bloc précédent ou avancer au suivant. Au repos, le premier clic sur précédent lit le dernier bloc disponible, puis les clics suivants remontent l’historique. Griser les flèches aux limites.
- Chaque action lit uniquement le bloc choisi ; Option peut couper cette lecture. Les blocs des conversations restées silencieuses doivent aussi être accessibles après sélection de la conversation.
- Limiter la navigation aux quatre ou cinq derniers messages par conversation, en conservant les blocs de chaque message pour la relecture. La limite porte sur les messages, pas sur le nombre total de blocs.
- Concevoir cette mémoire récente avec des ressources bornées ; sa constitution ne doit pas réintroduire la lecture intégrale des journaux.

### Notifications résumées des conversations annexes

- Ajouter au lot les notifications vocales courtes des réponses finales des conversations annexes. Leurs messages de progression restent silencieux.
- Règles fondamentales : une réponse annexe ne désigne jamais sa conversation comme principale et sa notification ne coupe jamais une lecture de la conversation principale.
- Format retenu : un son doux et distinctif, les trois premiers mots du titre affiché de la tâche, puis un résumé factuel très court en une phrase. Utiliser le titre Codex existant, sans nom audio dédié ni formule « nouvelle réponse dans ».
- Extraction locale confirmée pour commencer : sélectionner une courte phrase du texte lisible de la réponse finale, sans lire le code ni appeler une IA externe. Une éventuelle synthèse reformulée reste une évolution ultérieure, à décider séparément.
- Attendre dix secondes après la fin d’une lecture principale avant de diffuser les notifications en attente ; préserver la priorité de la conversation principale.
- Regrouper les notifications accumulées en une rafale, avec environ deux secondes entre elles. Une seule interruption avec Option abandonne toute la rafale, y compris ses notifications restantes, sans reprise automatique.
- Respecter la désactivation globale de la voix ; sa réactivation ne doit pas rejouer un ancien ensemble de notifications.

### Installation et mises à jour

- Préparer d’abord la signature Developer ID Application et la notarisation Apple, sans modifier les certificats ni les réglages de My Coaches ou Real Score. Cette préparation a été autorisée séparément ; elle ne publie ni ne réinstalle l’app.
- Ajouter ensuite un bouton de recherche et d’installation des mises à jour dans l’app, avec Sparkle et les versions hébergées sur GitHub. Prévoir une première installation manuelle pour amorcer ce mécanisme et valider le remplacement ainsi que le redémarrage effectifs.
- Distinguer la mise à jour du contrôleur MacBook de celle du service Mac mini. Ne pas promettre que la notarisation évitera toute nouvelle autorisation de confidentialité macOS.

Avancement de cette brique, autorisée séparément : signature Developer ID et
notarisation validées sur un DMG de test ; bouton Sparkle manuel intégré dans
les sources, avec dépendance verrouillée, framework embarqué, signature des
composants et clé Sparkle dédiée dans le trousseau. Aucun déploiement ni
publication. Les copies de test avec Sparkle sont notariées ; téléchargement,
contrôle des signatures, erreurs et annulation sont vérifiés dans l’interface.
Après acceptation par l’utilisateur de l’accès au dossier Documents, le test
réel a validé le remplacement, le redémarrage sur la nouvelle version, sa
signature Apple et la conservation du réglage témoin isolé. Les copies et le
serveur de test sont arrêtés. Restent la première version distribuée, son
catalogue HTTPS signé et les vérifications sur le MacBook avec les vrais
réglages SSH/Option. Détails dans UPDATES.md.

Ces éléments font partie du même lot. Les tests de développement restent
progressifs ; la recette utilisateur et la distribution sont regroupées à la fin.
Le détail de cette recette est dans [BATCH-VALIDATION.md](BATCH-VALIDATION.md).
