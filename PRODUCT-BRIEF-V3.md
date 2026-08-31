# Codex Voice V3 — brief produit vivant

## Intention

Codex Voice V3 doit préserver la sensation d'une conversation vocale en push-to-talk avec Codex lorsque Codex, la synthèse vocale et l'utilisateur se trouvent sur des appareils différents.

Promesse de travail :

> Je parle depuis l'appareil que j'ai en main, la bonne conversation Codex me répond depuis le Mac qui travaille, et dès que je reprends la parole elle se tait.

## Contexte d'usage

- Codex et les tâches de développement s'exécutent principalement sur un Mac mini sans écran ni clavier.
- Le MacBook Pro est la surface de contrôle principale et reste disponible pendant les sessions de travail.
- L'iPad est une surface secondaire de confort. Il n'a pas besoin de proposer toutes les capacités de la V3 et certaines fonctions peuvent légitimement nécessiter le MacBook Pro.
- Les appareils se trouvent généralement sur le même réseau local.
- La sortie audio du Mac mini est satisfaisante : la V3 n'a pas besoin, par défaut, de diffuser l'audio vers l'appareil de contrôle.
- Plusieurs conversations et plusieurs projets peuvent travailler simultanément.
- Une ou deux conversations sont souvent importantes pendant une session de travail ; d'autres sont de petites tâches secondaires.

## Objectif de publication

Codex Voice V3 a vocation à devenir un projet open source publié dans l'organisation GitHub [`defrenne-lab`](https://github.com/organizations/defrenne-lab).

Le dépôt doit remplir simultanément trois rôles :

- assurer le versioning et le partage normal des sources ;
- permettre à d'autres utilisateurs de comprendre, installer et adapter la solution ;
- constituer une démonstration crédible de conception, d'intégration et de déploiement de solutions d'intelligence artificielle.

La présentation publique doit mettre en valeur le problème réel, les arbitrages produit, l'architecture distribuée, la fiabilité et l'expérience d'exploitation. Elle ne doit pas chercher à présenter le projet comme un exercice de volume de code : sa valeur réside dans la qualité du besoin identifié et de la solution déployable.

Conséquences dès le développement :

- aucune transcription, aucun jeton, aucun chemin utilisateur absolu et aucune trace personnelle ne doit être versionné ;
- les diagnostics bruts et les états locaux doivent rester ignorés par Git ;
- les choix d'architecture importants doivent être consignés avec leurs preuves ;
- la construction et les tests doivent pouvoir être reproduits sur une installation propre ;
- le futur dépôt devra proposer une licence, un guide d'installation, une démonstration courte et une architecture lisible ;
- la configuration propre au Mac mini, au réseau et aux voix doit rester séparée du code partageable.

## Principes déjà retenus

1. Le push-to-talk signifie « l'utilisateur reprend la parole » et doit arrêter immédiatement la lecture, même à distance.
2. Une conversation Codex ne doit jamais interrompre la lecture d'une autre conversation Codex.
3. En cas d'ambiguïté sur la conversation à lire, le silence est le comportement sûr.
4. Les réponses non lues restent disponibles et visibles ; elles ne sont pas perdues.
5. Codex fournit déjà ses propres indicateurs de nouveauté. La V3 ne doit pas recréer inutilement un centre de notifications complet.
6. macOS TTS constitue le socle de fiabilité. Voxtral ne doit plus dicter l'architecture de la V3.
7. Les appareils n'ont pas à offrir une parité fonctionnelle : le MacBook Pro est le contrôleur complet ; l'iPad peut rester une télécommande légère.
8. L'audio complète la lecture à l'écran ; il ne constitue pas un flux autonome que l'application doit absolument terminer.
9. Une interruption volontaire abandonne la lecture automatique en cours. Elle ne déclenche jamais de reprise automatique ultérieure.
10. La navigation volontaire vers un bloc d'une autre conversation doit également amener cette conversation au premier plan dans Codex, si l'intégration le permet.
11. Les informations provisoires ne sont lues que dans la conversation principale, en réponse directe à la dernière intervention de l'utilisateur. Les conversations parallèles restent silencieuses pendant leur travail.

## Modèle mental à explorer

La V3 distingue trois notions :

- **Session de travail** : ensemble durable des conversations utilisées pendant la période courante, alimenté automatiquement lorsqu'un message est envoyé.
- **Conversation principale** : conversation qui répond directement à la dernière intervention de l'utilisateur et possède le dialogue vocal au premier plan.
- **État global de la voix** : autorisation simple donnée à Codex Voice de produire ou non de l'audio pendant la période courante.
- **Réponse en attente** : réponse terminée mais non lue, signalée visuellement et accessible en un clic.
- **Notification vocale de fin** : annonce très courte indiquant qu'une conversation parallèle a terminé et résumant son résultat en une ligne, sans lire sa réponse complète.
- **Bloc de lecture** : paragraphe ou unité successive visible dans une réponse Codex, que l'utilisateur peut réécouter explicitement.
- **Chronologie globale de lecture** : suite ordonnée des blocs disponibles dans les conversations de la session, qu'ils aient déjà été lus ou qu'ils soient restés silencieux.
- **Élément provisoire** : texte de raisonnement ou de progression que Codex peut encore réécrire ou supprimer avant sa réponse finale.
- **Bloc final** : paragraphe stabilisé dans la réponse finale, apte à entrer durablement dans la chronologie globale.
- **Version parlée** : représentation audio d'un bloc. Elle peut reprendre le texte, l'abréger ou le résumer selon sa longueur et sa densité technique.

Seul l'utilisateur peut interrompre brutalement une lecture. Une nouvelle réponse Codex attend son tour ou une action explicite.

La chronologie globale fournit le mécanisme de récupération : lorsqu'une réponse arrive dans une autre conversation pendant une lecture, ses blocs sont ajoutés silencieusement à la chronologie. L'utilisateur peut ensuite les retrouver avec la navigation précédent/suivant, sans qu'ils aient eu besoin d'interrompre la lecture initiale.

### Priorité des prises de parole

1. La reprise de parole de l'utilisateur est prioritaire sur tout et interrompt immédiatement l'audio.
2. La lecture de la conversation principale ne peut jamais être interrompue par une autre conversation.
3. Une conversation parallèle ne lit ni ses phrases provisoires ni sa réponse complète automatiquement.
4. Lorsqu'elle termine, elle peut préparer une notification vocale de fin très courte.
5. Cette notification attend que le canal audio soit libre et que l'utilisateur ne soit pas en train de parler ou d'enregistrer une demande.
6. La réponse complète reste en attente dans la chronologie globale.
7. Si plusieurs tâches parallèles terminent presque ensemble, leurs notifications doivent pouvoir être regroupées afin d'éviter une succession d'annonces.
8. La voix globalement désactivée ou la sourdine supprime également ces notifications.

### Temporisation des notifications parallèles

- Après la fin ou l'interruption d'une lecture de la conversation principale, aucune notification parallèle ne doit être prononcée pendant dix secondes.
- Cette fenêtre laisse le temps à l'utilisateur de poursuivre tranquillement la lecture du texte à l'écran.
- Toute nouvelle prise de parole de l'utilisateur ou nouvelle lecture principale suspend les notifications et relance la période de calme.
- Les réponses parallèles qui arrivent pendant cette période sont accumulées plutôt qu'annoncées séparément.
- Lorsque la période de calme se termine, les notifications accumulées sont idéalement regroupées en un seul lot précédé d'une seule signature sonore.
- À l'intérieur du lot, les différentes conversations peuvent être séparées par environ deux secondes afin de rester faciles à distinguer.
- Le lot peut contenir tous les résumés accumulés ; il n'est pas tronqué arbitrairement après un nombre fixe de conversations.
- Le lot entier constitue une seule unité audio interruptible.
- Une seule pression sur Option depuis le MacBook Pro arrête immédiatement le résumé en cours et annule tous les résumés restants du lot.
- Sur iPad, le comportement cible est identique lorsque l'utilisateur touche le bouton micro de Codex, sous réserve de faisabilité technique.
- Un lot volontairement interrompu ne reprend pas et ses éléments restants ne sont pas annoncés à nouveau plus tard.
- L'annulation du lot n'efface pas les réponses complètes : elles restent disponibles et signalées dans la chronologie globale.
- Le système n'a aucune exigence de temps réel pour ces annonces : préserver le calme et la compréhension est prioritaire sur leur immédiateté.

Exemple cible :

> `[son doux]` Optimisation GitHub. Les traitements sont terminés et trois optimisations ont été appliquées.

### Forme d'une notification vocale de fin

La notification combine deux parties :

1. **Signature sonore fixe** : un son doux et distinctif indiquant une notification issue d'une conversation parallèle.
2. **Nom parlé** : version courte du titre de la conversation.
3. **Résumé variable** : une seule phrase courte présentant le résultat principal.

La signature sonore remplace entièrement la formule « Nouvelle réponse dans ». Une courte pause sépare le nom de la conversation du résumé.

Le résumé doit :

- commencer par le résultat ou l'état final plutôt que par le détail du travail ;
- rester assez court pour ne pas devenir une seconde lecture de la réponse ;
- éviter le code, les chemins, les commandes et les listes techniques ;
- rester strictement fondé sur la réponse finale ;
- se rabattre sur le seul message factuel lorsqu'aucun résumé fiable ne peut être produit.

### Identité sonore et nom parlé

- Un son très bref et reconnaissable précède chaque notification issue d'une conversation parallèle et suffit à en annoncer la nature.
- Ce son sert de signature acoustique ; il doit être discret, non alarmant et distinct d'une erreur ou du début d'une lecture principale.
- Son niveau suit le volume et la sourdine de Codex Voice.
- Le nom source est le titre de tâche déjà affiché dans Codex. La V3 n'introduit pas de champ de nommage supplémentaire.
- Le nom parlé utilise par défaut les trois premiers mots significatifs de ce titre.
- L'utilisateur peut donc améliorer naturellement le nom parlé en renommant la tâche dans Codex, sans gérer une seconde convention propre à Codex Voice.
- Si deux tâches de la session partagent les mêmes trois premiers mots, le système peut ajouter le nombre minimal de mots nécessaire pour les distinguer.

Exemple :

- Titre Codex : « Améliorer la fusion des threads ».
- Nom parlé : « Améliorer la fusion ».
- Notification : `[son doux] Améliorer la fusion. Les traitements sont terminés et trois optimisations ont été appliquées.`

Exemple avec plusieurs réponses accumulées :

> `[son doux]` Trois conversations parallèles ont terminé. Améliorer la fusion… Les traitements sont terminés et trois optimisations ont été appliquées. `[pause courte]` Nettoyer les tests… Douze tests ont été corrigés. `[pause courte]` Préparer la documentation… La nouvelle version est prête à être relue.

## Cycle de vie du contenu

Codex peut afficher des paragraphes pendant son raisonnement, puis les réécrire ou les supprimer avant de produire sa réponse finale. La V3 ne doit donc pas traiter tout texte visible comme un élément immuable.

- Les éléments provisoires peuvent alimenter une lecture immédiate et légère de la progression.
- Cette lecture provisoire est réservée à la conversation principale.
- Les conversations parallèles ne lisent jamais leurs phrases de progression, même lorsque le canal audio semble libre.
- Ils ne deviennent pas automatiquement des entrées durables de la chronologie globale.
- La réponse finale constitue la source stable à découper en blocs navigables.
- Lorsqu'un contenu provisoire réapparaît dans la réponse finale, la V3 doit éviter autant que possible de le lire deux fois.
- Lorsqu'un contenu provisoire disparaît, il ne doit pas rester présenté comme un paragraphe final réécoutable.
- L'historique durable doit privilégier la cohérence avec ce qui reste réellement visible à l'écran.

## Adaptation pour l'oral

La version parlée d'un bloc n'est pas nécessairement sa transcription littérale.

- Un paragraphe narratif court peut être lu presque tel quel.
- Un paragraphe très long peut être raccourci en conservant sa conclusion et les informations utiles à la conversation.
- Un passage dense en code, chemins, commandes ou détails techniques peut être résumé par une transition compréhensible au lieu d'être intégralement supprimé.
- Le bloc source reste accessible à l'écran ; l'audio sert à maintenir le fil, pas à reproduire chaque caractère.
- Toute version résumée doit rester rattachée au bloc source et identifiable comme telle dans l'état de lecture.

## Contrôles essentiels

### Interruption universelle

- Sur MacBook Pro, Option est le geste universel pour abandonner immédiatement le contenu audio courant et reprendre éventuellement la parole.
- Ce geste s'applique de la même manière à une réponse principale, une réécoute explicite, une notification parallèle ou un lot de notifications.
- Une interruption signifie « ce contenu audio ne m'intéresse plus » : la lecture ou le lot disparaît et ne reprend pas automatiquement.
- L'interruption ne supprime jamais le texte source ni les blocs de la chronologie ; elle supprime uniquement leur manifestation audio automatique en cours.
- Sur iPad, le bouton micro de Codex constitue le comportement cible équivalent, sous réserve de faisabilité technique.

### Volume

- Le volume de Codex Voice doit être réglable facilement depuis l'appareil de contrôle, sans dépendre des boutons physiques du Mac mini.
- Le réglage doit permettre de s'adapter rapidement au bruit ambiant ou à une écoute douce le soir.
- Une mise en sourdine immédiate doit être disponible.
- Le volume de la voix devrait être distinct, autant que possible, du volume général du Mac mini.
- L'état courant doit être visible sur le MacBook Pro et cohérent sur les autres surfaces qui exposent ce contrôle.

### Activation globale de la voix

- L'utilisateur doit pouvoir activer ou désactiver toute lecture automatique en une action.
- L'état actif ou inactif doit être impossible à confondre visuellement.
- Quand la voix est désactivée, aucune tâche terminée plus tard ne doit produire de son.
- L'état désactivé est persistant : un redémarrage du Mac mini, une relance de Codex Voice ou une reconnexion du contrôleur ne réactive jamais la voix automatiquement.
- Seule une action volontaire de l'utilisateur peut réactiver la voix.
- Réactiver la voix ne doit pas déclencher la lecture automatique d'un ancien stock de réponses. Les anciennes réponses restent consultables et peuvent être relues volontairement.
- Ce contrôle doit être accessible depuis le MacBook Pro et localement lorsque le Mac mini est accessible.
- Son accès depuis l'iPad est souhaitable pour le confort, sans imposer que toute l'administration de la voix soit disponible sur iPad.

## Scénarios concrets

### 1. Une conversation principale en push-to-talk distant

**Situation**

L'utilisateur travaille dans une conversation A depuis son MacBook Pro. Codex et Codex Voice fonctionnent sur le Mac mini, qui produit le son.

**Déroulement attendu**

1. Pendant la dictée, Codex fournit déjà le retour visuel nécessaire. Codex Voice n'ajoute ni fenêtre ni animation redondante.
2. L'utilisateur envoie une demande dans A. A devient ou reste la conversation vocale courante.
3. La réponse commence à être lue assez tôt, sans attendre inutilement la fin d'un long message.
4. Pendant la lecture seulement, un indicateur V3 discret montre qu'une réponse est en cours de lecture et identifie au minimum la conversation concernée.
5. Cet indicateur permet d'arrêter la lecture en un clic, mais le geste principal sur MacBook Pro reste la touche Option.
6. Lorsque l'utilisateur appuie sur Option, la dictée démarre dans Codex sur le MacBook Pro et la lecture sur le Mac mini s'arrête avec une sensation d'immédiateté.
7. L'interruption met définitivement fin à cette lecture automatique. L'utilisateur continue généralement à lire la réponse directement à l'écran.
8. Sur iPad, le comportement idéal est que le toucher du bouton micro de Codex transmette la même intention de reprise de parole et coupe d'abord la voix du Mac mini. La faisabilité de cette intégration doit être validée ; une commande dédiée légère pourra servir de repli si l'événement du micro Codex n'est pas observable.

**Critère de réussite**

L'utilisateur retrouve la même sensation de prise de parole qu'avec la V2 installée sur un seul Mac.

**Hiérarchie visuelle envisagée**

- Quand l'utilisateur parle : aucun nouveau visuel, puisque Codex montre déjà l'enregistrement.
- Quand Codex Voice lit : petit indicateur « en cours de lecture », nom de la conversation et action d'arrêt immédiat.
- Le contenu exact du message peut rester absent ou se limiter à un très court extrait ; cette information n'est pas encore considérée comme nécessaire.
- Quand rien n'est lu : l'indicateur peut disparaître ou revenir à un état très discret.
- Le volume et les réglages détaillés appartiennent à la vue développée, pas nécessairement à l'indicateur minimal.

**Interruption et réécoute**

- Arrêter une lecture n'est pas la mettre en pause.
- Après une interruption volontaire, la V3 ne reprend jamais automatiquement le texte restant.
- L'utilisateur peut demander explicitement la réécoute d'un bloc précédent ou suivant.
- La navigation porte idéalement sur les paragraphes successifs visibles dans Codex, et non sur une position temporelle arbitraire dans le flux audio.
- Une réécoute recommence le bloc sélectionné depuis son début.
- La navigation parcourt d'abord les blocs de la réponse courante, puis continue dans les réponses précédentes ou suivantes.
- Elle peut traverser les différentes conversations de la session.
- Les blocs jamais prononcés parce qu'ils sont arrivés pendant une autre lecture font tout de même partie de cette chronologie.
- Chaque bloc doit conserver au minimum l'identité de sa conversation, son ordre dans la réponse et son état lu ou en attente.
- Lorsqu'elle traverse vers une autre conversation, la navigation amène idéalement cette conversation au premier plan dans Codex afin que l'écran et l'audio restent cohérents.

### 2. Deux projets importants pendant la même session

**Situation**

Les conversations A et B correspondent aux deux projets importants de la soirée. A est en cours de lecture lorsque B termine une tâche.

**Déroulement attendu**

1. A et B sont visibles comme faisant partie de la session de travail.
2. A reste audible sans être interrompue.
3. B passe visuellement à l'état « réponse en attente ».
4. Les phrases provisoires produites par B pendant son travail n'ont jamais été lues, puisque B travaillait en parallèle de la conversation principale.
5. Si A est en cours de lecture lorsque B termine, B n'émet aucun son et attend.
6. Lorsque le canal redevient libre, B peut produire une notification vocale de fin d'une seule ligne, sans lancer sa réponse complète.
7. L'utilisateur peut passer à B en un clic, l'ignorer pour le moment ou continuer son travail dans A.
8. S'il choisit B, la lecture de B commence. La lecture automatique de A est considérée comme abandonnée si elle a été volontairement interrompue.
9. Le retour vers A est possible en une action simple pour réécouter explicitement un paragraphe ou un bloc, sans reprendre automatiquement l'ancien flux à sa position temporelle.
10. Sans sélectionner directement B, l'utilisateur peut également atteindre ses blocs en avançant naturellement dans la chronologie globale de lecture.

**Décision**

Après la fin complète de A, B ne lance jamais automatiquement la lecture intégrale de sa réponse. Après la période de calme, elle peut seulement produire sa notification vocale de fin. La lecture complète de B nécessite une sélection ou une navigation explicite de l'utilisateur.

### 3. Une petite tâche doit rester silencieuse

**Situation**

Pendant qu'il travaille principalement dans A, l'utilisateur envoie une petite tâche ponctuelle dans C.

**Déroulement attendu**

1. Avant ou au moment d'envoyer la petite tâche, l'utilisateur met globalement Codex Voice en pause avec une action très simple.
2. Il n'a pas à créer de règle propre à C ni à administrer le droit de parler de chaque conversation.
3. Pendant la pause, aucune conversation ne produit de phrases provisoires, de lecture finale ou de notification vocale de fin.
4. Lorsque C termine, aucun son n'est produit. Codex conserve sa boule bleue et les blocs finaux peuvent rester disponibles dans la chronologie.
5. L'utilisateur réactive lui-même Codex Voice lorsqu'il souhaite retrouver la conversation vocale.
6. La réactivation ne lit pas C ni les autres réponses accumulées pendant la pause.
7. Seules les nouvelles productions postérieures à la réactivation peuvent reprendre le comportement audio normal ; les anciennes restent accessibles par une action volontaire.

**Critère de réussite**

La délégation de petites tâches reste pratique sans configuration par conversation et sans risque de lecture différée inattendue.

**Piste ultérieure d'interface**

Une instruction utilisateur explicite comme « coupe Codex Voice » pourrait un jour piloter l'état global depuis la conversation. Cette piste ne fait pas partie du comportement de base à ce stade. Si elle est explorée, seules des commandes utilisateur explicites et authentifiées devront être interprétées comme contrôles ; le texte produit par l'assistant ne devra jamais pouvoir déclencher ces actions.

### 4. Fin de soirée et tâches nocturnes

**Situation**

L'utilisateur termine sa session interactive mais laisse plusieurs tâches tourner sur le Mac mini pendant la nuit.

**Déroulement attendu**

1. Depuis le MacBook Pro — ou depuis l'iPad si ce contrôle léger y est proposé — il désactive globalement la voix ou active la sourdine.
2. L'interface confirme clairement que le Mac mini restera silencieux.
3. Les tâches continuent normalement et leurs résultats restent signalés dans Codex.
4. Une tâche qui termine deux heures plus tard ne produit aucun son.
5. Un redémarrage nocturne du Mac mini ou une relance de l'application ne modifie pas cet état silencieux.
6. Le lendemain, l'utilisateur réactive explicitement la voix ; cette action ne lit pas spontanément les réponses accumulées pendant la nuit.
7. L'utilisateur peut consulter ou relire chaque réponse volontairement.

**Critère de réussite**

L'utilisateur peut laisser travailler le Mac mini sans craindre qu'il parle de façon inattendue lorsqu'il n'est plus en session vocale.

## Questions produit encore ouvertes

- Comment une conversation principale est-elle verrouillée ou libérée sans créer de gestion fastidieuse ?
- Quelle durée ou quel geste met fin à une session de travail et fait disparaître les conversations devenues anciennes ?
- À quoi doit ressembler l'indicateur visuel minimal sur macOS et sur iPad ?
- Quel sous-ensemble minimal de commandes apporte une vraie valeur sur iPad, sans chercher à reproduire le contrôleur complet du MacBook Pro ?
- Comment aligner de manière fiable les blocs audio avec les paragraphes successifs visibles dans l'interface Codex ?
- Quel ordre doit utiliser la chronologie lorsque plusieurs réponses et blocs deviennent disponibles presque simultanément ?
- Comment reconnaître qu'un paragraphe provisoire et un bloc final expriment la même information afin d'éviter une double lecture ?
- Quelle stratégie de résumé oral offre un bon équilibre entre fidélité, rapidité et simplicité opérationnelle ?
