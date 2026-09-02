# Codex Voice V3 — plan de contrôle distant

Date de validation : 31 août 2026

## Résultat

Le Mac mini expose maintenant un serveur WebSocket de contrôle vocal lié exclusivement à `127.0.0.1`. Un client macOS séparé, `codex-voice-remote`, sait consulter l'état et envoyer les commandes `interrupt`, `enable`, `disable`, `mute`, `unmute`, `volume`, `rate` et `voice`. L'app de barre de menu sait aussi charger et enregistrer le dictionnaire de prononciation.

Le transport traverse un tunnel SSH maintenu par l'app MacBook. Aucun port Codex Voice n'est publié sur le Wi-Fi et l'App Server de Codex n'est jamais exposé.

## Contrat du protocole

Le sous-protocole WebSocket est `codex-voice.v1`. Chaque requête JSON contient :

- la version du protocole ;
- un identifiant stable du client ;
- une séquence strictement positive ;
- un jeton d'autorisation ;
- une commande typée et sa valeur éventuelle.

Le serveur conserve la dernière séquence de chaque client pendant son exécution. Une séquence ancienne ou répétée reçoit une réponse `duplicate` et ne réapplique jamais la commande. `interruptAudio` reste donc idempotente, y compris lors d'une reconnexion incertaine.

Les messages sont limités à 64 Kio et le dictionnaire à 32 Kio. Le serveur peut publier un nouvel état aux connexions déjà authentifiées, ce qui alimente l'indicateur temps réel de l'app MacBook.

## État exposé

Une réponse authentifiée contient uniquement :

- activation, sourdine, volume système, vitesse et voix choisie ;
- présence d'une lecture et nombre d'unités en file ;
- identifiants et titre de la tâche actuellement lue ;
- type de lecture ;
- nombre de réponses parallèles en attente.
- catalogue des voix françaises installées, sans aucune donnée de transcript.

Le texte lu n'est jamais envoyé au contrôleur. Le contenu du dictionnaire est transmis uniquement en réponse à une commande explicite et authentifiée d'ouverture ou d'enregistrement. Une connexion non authentifiée ne reçoit ni état ni dictionnaire, même lorsqu'elle emploie une requête JSON valide.

## Jeton local

Au premier démarrage, le runtime crée un jeton aléatoire de 256 bits dans :

```text
~/.codex-voice/control-token
```

Le dossier possède les permissions `0700` et le fichier `0600`. Le jeton est un secret porteur : il ne doit être ni journalisé ni ajouté au dépôt Git.

Le runtime accepte `--control-token-file` pour les environnements de test. Son contenu n'est jamais affiché ; seul le chemin est indiqué.

## Utilisation à travers SSH

Sur le Mac mini, le runtime final démarrera de cette manière :

```shell
swift run -c release codex-voice-local --disable-voice --forever
```

Pour préparer le MacBook une première fois, copier le jeton puis vérifier qu'une connexion par clé ne demande pas de mot de passe :

```shell
install -d -m 700 ~/.codex-voice
scp macmini:~/.codex-voice/control-token ~/.codex-voice/control-token
chmod 600 ~/.codex-voice/control-token
ssh macmini true
```

La cible SSH est conservée uniquement dans la configuration privée du MacBook :

```shell
printf '%s\n' 'CODEX_VOICE_SSH_TARGET=macmini' > ~/.codex-voice/.env
chmod 600 ~/.codex-voice/.env
```

Au lancement, l'app exécute `/usr/bin/ssh` en mode non interactif, ouvre uniquement `127.0.0.1:48731`, utilise les keep-alive SSH et recrée le tunnel après une coupure. Elle ne stocke et ne demande aucun mot de passe. Sans cette variable, un tunnel lancé manuellement reste compatible.

Le client parle alors à son propre localhost :

```shell
codex-voice-remote state
codex-voice-remote interrupt
codex-voice-remote volume 0.45
codex-voice-remote rate 0.53
codex-voice-remote voice com.apple.voice.enhanced.fr-FR.Aurelie
codex-voice-remote mute
codex-voice-remote disable
```

Par sécurité, le client refuse une URL `ws://` qui ne vise pas `localhost`. Une future connexion directe devra obligatoirement employer `wss://` avec l'appairage prévu pour l'iPad.

## Validation

La suite compte 53 tests. Elle vérifie notamment l'authentification, l'absence de texte dans l'état, la mutation des réglages, l'interruption de toute la file, la déduplication des séquences, les permissions privées du jeton, le parseur `.env` et la construction restrictive de la commande SSH.

Le vrai serveur Network.framework et le vrai client URLSession ont également été exécutés ensemble sur `127.0.0.1` :

- connexion avec le sous-protocole V1 validée ;
- `getState`, `setVolume` et `interruptAudio` validées ;
- une séquence obsolète n'a pas modifié le volume ;
- un mauvais jeton a été refusé sans état ;
- un serveur absent provoque un échec immédiat ;
- l'aller-retour local complet de `interruptAudio`, lancement du client inclus, a été mesuré à environ `0,01 s` ;
- aucune erreur parasite n'est journalisée lors d'une fermeture normale du client.

La voix est restée désactivée pendant toute la validation et le volume a été remis à `0,8`. Les jetons temporaires de test ont été supprimés.

## App macOS de barre de menu

`codex-voice-menu` est le contrôleur principal destiné au MacBook Pro. Il conserve une connexion WebSocket ouverte, reçoit les changements d'état du Mac mini, se reconnecte automatiquement et expose les contrôles essentiels dans une popin native :

- état de connexion et conversation actuellement lue ;
- activation globale de la voix ;
- volume système réel du Mac mini ;
- choix compact entre Thomas et Aurélie lorsque ces voix sont installées ;
- vitesse lente, normale, rapide ou très rapide selon les valeurs éprouvées dans la V2 ;
- ouverture du dictionnaire dans TextEdit et synchronisation des enregistrements vers le Mac mini ;
- interruption immédiate de toute la file audio ;
- ouverture directe du partage d’écran vers l’hôte déjà configuré pour SSH, même lorsque le contrôle vocal est hors ligne ;
- observation passive de la touche Option, sans empêcher Codex de recevoir le même événement.

L'app utilise par défaut le tunnel local et le jeton déjà documentés. Elle charge d'abord `~/.codex-voice/.env`, puis laisse les variables du processus les remplacer. Les réglages pris en charge sont `CODEX_VOICE_SSH_TARGET`, `CODEX_VOICE_REMOTE_URL`, `CODEX_VOICE_TOKEN_FILE` et `CODEX_VOICE_DEVICE_NAME`. Les arguments `--url`, `--token-file` et `--device-name` restent disponibles.

Le mode `--preview` affiche l'état de référence sans réseau et sans produire de son. Il sert uniquement à vérifier le rendu et à préparer les captures de démonstration.

Pour construire un bundle macOS local :

```shell
chmod +x Scripts/build-remote-app.sh
Scripts/build-remote-app.sh
open ".build/Codex Voice 3.app"
```

Au premier lancement, macOS peut demander l'autorisation de surveiller le clavier. Cette permission sert uniquement à observer Option ; l'événement n'est jamais intercepté ni modifié.

Un clic gauche sur le halo ouvre les contrôles. Un clic droit propose de quitter proprement l'app sans ajouter de commande permanente dans la popin principale.

Le tunnel SSH appartient au cycle de vie de l'app : il démarre avec elle, se relance après une déconnexion et s'arrête lors d'une fermeture normale. L'appairage direct sans SSH reste une brique ultérieure destinée notamment à l'iPad.

## Installation du service sur le Mac mini

Le runtime peut être installé comme LaunchAgent utilisateur, sans droit administrateur :

```shell
Scripts/install-local-service.sh
```

Le script place un binaire stable dans `~/Library/Application Support/Codex Voice 3/bin`, installe `lab.defrenne.codexvoice3.local.plist` et conserve les journaux dans le même dossier d'application. Il ne force pas l'activation de la voix : une installation neuve reste désactivée et les réglages explicites sont ensuite persistés.

Le LaunchAgent est classé `Interactive`. Une première exécution en `Background` a provoqué des cycles Core Audio sautés sous charge ; la lecture vocale exige ici la même réactivité qu'une application interactive. L'installateur tolère également le court délai asynchrone avec lequel `launchctl` retire parfois l'ancienne instance pendant une mise à jour.

## Paquet destiné au MacBook

Le paquet signé localement et préservant le bundle macOS est produit avec :

```shell
Scripts/package-remote-app.sh
```

Il crée un DMG versionné et affiche son empreinte SHA-256. Le MacBook récupère séparément cette image et le jeton privé via SSH ; le jeton ne fait jamais partie du paquet.
