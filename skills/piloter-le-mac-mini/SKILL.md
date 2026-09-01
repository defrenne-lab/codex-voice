---
name: piloter-le-mac-mini
description: Piloter le volume système du Mac mini et les commandes de Codex Voice 3 depuis une conversation. Utiliser pour consulter l’état audio, régler le volume du Mac ou de la voix, changer la vitesse, activer ou désactiver la voix, ou interrompre la lecture.
---

# Piloter le Mac mini

Utiliser `scripts/control_mac_mini.sh` comme unique interface de commande. Le script agit localement sur le Mac mini et pilote Codex Voice par son API de contrôle sur loopback.

## Traduire la demande

- État du son ou de la voix : `scripts/control_mac_mini.sh status`
- Volume du Mac mini ou volume système, en pourcentage : `scripts/control_mac_mini.sh system-volume <0-100>`
- Volume de Codex Voice, de la lecture ou de la voix, en pourcentage : `scripts/control_mac_mini.sh voice-volume <0-100>`
- Vitesse lente, normale, rapide ou très rapide : `scripts/control_mac_mini.sh voice-speed slow|normal|fast|very-fast`
- Activer durablement la voix : `scripts/control_mac_mini.sh voice-on`
- Désactiver durablement la voix : `scripts/control_mac_mini.sh voice-off`
- Couper seulement la lecture en cours et sa file : `scripts/control_mac_mini.sh stop`

Une demande de « volume » sans autre précision désigne le volume système. Toujours indiquer dans la réponse lequel des deux volumes a été modifié.

Ces actions sont immédiates, réversibles et ne nécessitent pas de confirmation supplémentaire lorsque la valeur ou l’action est explicite. Ne pas inventer d’autres commandes du Mac mini : si une capacité demandée n’existe pas dans le script, l’indiquer avant toute modification du système.

Le script accède au volume système et au service WebSocket local hors de la sandbox du projet. Si son exécution est refusée ou si AppleScript ne charge pas ses commandes audio dans la sandbox, réexécuter le script complet avec l’autorisation hôte appropriée ; ne pas décomposer ni remplacer ses commandes.

Si le contrôleur Codex Voice installé est absent, signaler que le service local doit être réinstallé depuis le dépôt Codex Voice 3. Ne pas exposer le port de contrôle sur le réseau et ne pas afficher le contenu du jeton.
