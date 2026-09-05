# Backlog

## Lot v0.2.1 — livré

Le 5 septembre 2026, après la recette de v0.2.0, l’utilisateur demande une petite
version pour le bouton Stop, puis y ajoute la présentation de la recherche de
mise à jour. Périmètre : les deux changements d’interface ci-dessous seulement.
Le service Mac mini reste inchangé. La v0.2.1/build 12 est publiée sur GitHub
avec son DMG notarié et son catalogue Sparkle signé, vérifiés après téléchargement
public. Le remplacement réel depuis v0.2.0 reste à confirmer sur le MacBook.
Suivi dans RELEASE-VALIDATION-0.2.1.md.

### Arrêter une relecture sans fermer la popover

Demande du 5 septembre 2026, pendant la recette utilisateur de v0.2.0.
Implémenté pour v0.2.1 à la demande de l’utilisateur après la recette.

- Ajouter un petit bouton d’arrêt à côté des flèches précédent/suivant de l’historique.
- Un clic coupe la relecture en cours, comme Option pour l’audio, mais laisse la popover ouverte pour continuer à naviguer.
- Ne pas désactiver globalement la voix ni changer la conversation principale ; ne pas reprendre automatiquement la lecture interrompue.
- Conserver des contrôles discrets, cohérents avec les deux flèches existantes.

### Clarifier le bouton de recherche de mise à jour

Retour du 5 septembre 2026 : la vérification fonctionne sur le MacBook, mais
l’icône à droite et les points de suspension donnent l’impression d’une
recherche permanente. Retouche ajoutée à v0.2.1 à sa demande.

- Au repos, afficher « Rechercher une mise à jour », sans points de suspension ni petite icône à droite.
- Rendre explicite qu’il s’agit d’un bouton à actionner, pas d’une opération en cours.
- Ne montrer un éventuel indicateur d’activité que pendant une recherche réellement déclenchée ; conserver le fonctionnement manuel existant.

## Prochaines versions — retours d’usage

### Ne pas dicter les adresses web

Le 5 septembre 2026, l’utilisateur signale une lecture du libellé suivie de
l’adresse HTTP/www. Souhait : garder le libellé du lien, ignorer son adresse.
Cette modification a été retirée explicitement de v0.2.1 car elle nécessite
une mise à jour du service Mac mini, que l’utilisateur ne souhaite pas faire
maintenant. Le prototype local et ses tests spécifiques ont été retirés ;
aucun changement de lecture n’a été déployé. À reprendre dans un futur lot
incluant le service et à tester sur les liens Markdown, les adresses brutes,
les variantes échappées, la relecture et les notifications.

### Peaufiner le son des notifications annexes

Retour du 5 septembre 2026 : la phrase de notification est bien entendue et
le fonctionnement est jugé satisfaisant, mais aucun son distinctif n’est perçu
avant la phrase. Le signal sonore n’est donc pas validé à l’écoute.

- Diagnostiquer le signal avant de changer son niveau : le code prévoit le son macOS Glass avec un gain de 0,18 et une attente de 500 ms avant la voix ; le fichier système est présent. Ces constats ne prouvent pas que le signal a été joué ou qu’il est audible dans l’installation réelle.
- Souhait de confort : rendre la phrase de notification légèrement moins forte que la lecture principale, sans baisser le volume système ni la conversation principale.
- Contrainte explicite : appliquer seulement si un réglage existant le permet ; aucun développement supplémentaire demandé pendant la recette. La vérification montre qu’aucun volume distinct n’est exposé dans les réglages, l’API ou la skill ; toutes les phrases utilisent actuellement le même gain de synthèse. L’évolution reste donc au backlog, sans modification du code ni déploiement.

## Lot v0.2.0 — livraison

Le 5 septembre 2026, l’utilisateur a demandé de regrouper toutes ces
modifications et de ne faire qu’une installation/recette à la fin. La préparation
d’une version séparée pour Sparkle a donc été abandonnée. L’utilisateur a ensuite
autorisé la livraison complète, y compris la publication et le service Mac mini.

État des sources : correction du lecteur borné, mémoire de cinq messages,
sélection distante, flèches, notifications temporisées, pastille agrandie et
fond natif translucide intégrés. Les 101 tests automatisés passent, ainsi que
les huit garde-fous de distribution ; le rendu hors ligne a été inspecté.
Le contrôle natif automatisé a dépassé son délai et sa copie
d’aperçu a été fermée. L’utilisateur a depuis confirmé sur le MacBook que la
taille de la pastille et le fond translucide avec textes lisibles lui conviennent.
Le rendu avec « Réduire la transparence » reste à vérifier explicitement.

Le 5 septembre 2026, l’utilisateur a confirmé l’extraction locale pour cette
première version des notifications : une courte phrase issue de la réponse,
pas une synthèse IA reformulée. Aucun service externe ni clé API n’est nécessaire.
Le DMG v0.2.0/build 11 est signé Developer ID, notarié et accepté par Gatekeeper.
Le service Mac mini a été remplacé avec sauvegarde des binaires précédents ;
réglages, dictionnaire, jeton et LaunchAgent ont été vérifiés inchangés.
L’utilisateur a confirmé le 5 septembre 2026 l’installation sur le MacBook dès
le premier essai, la coupure avec Option, le changement de conversation
principale, la navigation dans l’historique, la recherche de mise à jour,
le volume, la vitesse, l’ouverture du dictionnaire et le partage d’écran.
La séance de recette guidée est terminée. Le son distinctif des notifications
reste non perçu ; les scénarios non vérifiés et le test reporté à l’usage réel
sont distingués des validations obtenues dans BATCH-VALIDATION.md.

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

Avancement de cette brique : signature Developer ID et notarisation validées
sur les copies de test puis sur le DMG v0.2.0 ; bouton Sparkle manuel intégré,
avec dépendance verrouillée, framework embarqué, signature des composants et
clé Sparkle dédiée dans le trousseau. Les copies de test sont notariées ; téléchargement,
contrôle des signatures, erreurs et annulation sont vérifiés dans l’interface.
Après acceptation par l’utilisateur de l’accès au dossier Documents, le test
réel a validé le remplacement, le redémarrage sur la nouvelle version, sa
signature Apple et la conservation du réglage témoin isolé. Les copies et le
serveur de test sont arrêtés. L’installation réelle sur le MacBook et la coupure
avec Option sont désormais confirmées par l’utilisateur, ainsi que la recherche
de mise à jour sur ce Mac. Le remplacement par une future version via ce bouton
reste distinct de cette vérification. Détails dans UPDATES.md.

Ces éléments font partie du même lot. Les tests de développement restent
progressifs ; la recette utilisateur et la distribution sont regroupées à la fin.
Le détail de cette recette est dans [BATCH-VALIDATION.md](BATCH-VALIDATION.md).
