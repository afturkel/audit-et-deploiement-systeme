# Rapport : audit et déploiement d'un système Linux

Projet SAE, BUT Informatique 3, parcours DACS.

Dépôt Git : https://github.com/afturkel/audit-et-deploiement-systeme

## 1. Objectif

Réaliser un outil qui audite un système Linux (Debian et Ubuntu), le rendre paramétrable, puis le déployer dans un conteneur Docker en comparant ce que voit le conteneur et ce que voit l'hôte.

Le dépôt contient le script (`code/sae-audit.rb`), le `Dockerfile`, le `compose.yaml` et un `README.md` qui explique l'utilisation.

## 2. Audit Linux : informations et sources

Pour chaque information, j'ai lu un fichier de `/proc`, `/sys` ou `/etc` quand c'était possible. Lire un fichier est plus simple que lancer une commande. Cela permet aussi de lire les fichiers d'un autre dossier avec l'option `-r`, ce qui est utile avec Docker. Je n'ai utilisé une commande que lorsqu'il n'y avait pas de fichier simple.

| Information            | Source                                                     | Root nécessaire ?                                                                        | Remarque                                     |
| ---------------------- | ---------------------------------------------------------- | ---------------------------------------------------------------------------------------- | -------------------------------------------- |
| nom de la machine      | `/proc/sys/kernel/hostname`                                | non                                                                                      |                                              |
| noyau                  | `/proc/sys/kernel/osrelease`                               | non                                                                                      |                                              |
| distribution           | `/etc/os-release`                                          | non                                                                                      | on garde `PRETTY_NAME`, `NAME`, `VERSION_ID` |
| uptime                 | `/proc/uptime`                                             | non                                                                                      | premier nombre, en secondes                  |
| charge moyenne         | `/proc/loadavg`                                            | non                                                                                      | 1, 5 et 15 minutes                           |
| mémoire et swap        | `/proc/meminfo`                                            | non                                                                                      | valeurs en kB converties en octets           |
| interfaces réseau      | `/sys/class/net` (état, MAC) et `ip -o addr` (adresses IP) | non                                                                                      |                                              |
| connexions             | `ss -H -tunap`                                             | non, mais le processus des connexions des autres utilisateurs n'est visible qu'avec root | TCP et UDP                                   |
| plage des UID humains  | `/etc/login.defs` (`UID_MIN`, `UID_MAX`)                   | non                                                                                      |                                              |
| utilisateurs humains   | `/etc/passwd`                                              | non                                                                                      | UID dans la plage                            |
| utilisateurs connectés | `/run/systemd/sessions/`                                   | non                                                                                      | un fichier par session                       |
| espace disque          | `df -B1`                                                   | non                                                                                      | types virtuels exclus                        |
| processus gourmands    | `ps -eo ... --sort=-pcpu` et `-pmem`                       | non                                                                                      | N premiers                                   |
| services               | `systemctl is-active` et `is-enabled`                      | non                                                                                      |                                              |

Choix à justifier :

- **Mémoire utilisée** : calculée avec `MemAvailable` et non `MemFree`, car la mémoire disponible compte le cache que le système peut libérer.
- **Utilisateurs humains** : le script n'écrit pas un numéro à l'avance (comme 1000). Il lit les limites `UID_MIN` et `UID_MAX` dans `/etc/login.defs`, et garde les comptes dont le numéro est entre les deux. Cela écarte `root`, les comptes du système et `nobody`.
- **Utilisateurs connectés** : on ignore les sessions de classe `manager`, qui sont des sessions internes de systemd et non des personnes. La date est en microsecondes, il faut la diviser par un million.
- **Service `ssh`** : sous Ubuntu, `ssh` peut être inactif alors que `ssh.socket` répond. Le script ajoute une note dans ce cas.

## 3. Le script Ruby

### Paramètres

| Option | Rôle | Défaut |
|---|---|---|
| `-n N` | nombre de processus par critère | 5 |
| `-s LISTE` | services à vérifier | `ssh,ssh.socket,cron,docker` |
| `-r CHEMIN` | racine des fichiers système | `/` |
| `-j FICHIER` | écrire le résultat en JSON avec la date | affichage à l'écran |
| `-h` | aide | |

Le script lit les options tapées après son nom (`ARGV`), deux par deux : l'option, puis sa valeur. Il s'arrête avec un message d'erreur et le code 1 dans quatre cas : une option inconnue, une option sans valeur, un nombre de processus inférieur à 1, ou un nom de service invalide. Le nom d'un service est ensuite copié dans une commande. Pour éviter qu'on y glisse une deuxième commande (par exemple `-s "cd;ls"`), le script refuse les noms qui contiennent autre chose que des lettres, des chiffres et `. _ @ : -`.

### Structure

Chaque information est récupérée par une petite méthode du script. Si l'une échoue, elle renvoie une erreur et le script continue avec les autres.

Le résultat s'affiche à l'écran, ou s'enregistre dans un fichier JSON. À l'écran, il y a une ligne par élément, avec des tailles lisibles (Ko, Mo, Go) et un uptime en jours, heures et minutes. Le fichier JSON contient la date, les paramètres et toutes les informations.

### Gestion des erreurs

- Fichier illisible ou commande qui échoue : une erreur est écrite dans le résultat, et le script continue.
- Commande absente (par exemple `ip` ou `ss` non installés) : le script s'arrête avec une erreur de Ruby. Ce cas n'est pas géré, parce que l'image Docker installe toutes les commandes dont le script a besoin.
- Sans droits root : certaines informations ne sont pas visibles (par exemple le processus des connexions des autres utilisateurs). Le script l'indique dans le résultat.

Tests faits : exécution normale, racine inexistante (`-r /nexiste` : onze erreurs écrites dans le résultat, le script ne plante pas), option invalide, et fichier JSON relu pour vérifier qu'il est valide.

## 4. Docker

### Image

L'image part de Debian 12 et contient Ruby et les outils que le script appelle (`ps`, `ip`, `ss`, `systemctl`). Le conteneur lance toujours le script, et les arguments de `docker run` lui sont transmis. Le `Dockerfile` est à la racine du dépôt.

### Conteneur sans option

| Information            | Résultat                 | Explication                                                                    |
| ---------------------- | ------------------------ | ------------------------------------------------------------------------------ |
| nom de la machine      | identifiant du conteneur | Docker donne son propre nom au conteneur                                       |
| distribution           | Debian 12                | le conteneur lit le fichier `/etc/os-release` de son image                     |
| noyau, uptime, mémoire | ceux de l'hôte           | le conteneur utilise le noyau de l'hôte                                        |
| interfaces             | `eth0` et `lo`           | le conteneur a son propre petit réseau                                         |
| processus              | ceux du conteneur        | le conteneur ne voit que ses propres processus                                 |
| services               | erreur                   | il n'y a pas de systemd (le programme qui gère les services) dans le conteneur |

D'après le test, on constate qu'un conteneur n'est pas une machine virtuelle : il utilise le noyau de l'hôte, mais il a son propre nom, son propre réseau, ses propres processus et ses propres fichiers.

### Conteneur qui audite l'hôte

```
docker run --rm \
  --pid=host --network=host --uts=host \
  -v /:/host:ro -v /run/systemd:/run/systemd:ro \
  --cap-add=SYS_PTRACE --security-opt apparmor=unconfined \
  -e SYSTEMD_IGNORE_CHROOT=1 \
  sae-audit -r /host
```

| Option                               | Rôle                                                                                    | Effet mesuré si on l'ajoute seule                                       |
| ------------------------------------ | --------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| `--uts=host`                         | voir le nom de l'hôte                                                                   | le nom devient celui de l'hôte                                          |
| `--pid=host`                         | voir les processus de l'hôte                                                            | les processus de l'hôte apparaissent                                    |
| `--network=host`                     | voir les interfaces et les connexions de l'hôte                                         | 5 interfaces et 62 connexions, mais sans le nom des processus           |
| `-v /:/host:ro` avec `-r /host`      | lire les fichiers de l'hôte                                                             | Ubuntu, utilisateurs et disque de l'hôte                                |
| `-v /run/systemd:/run/systemd:ro`    | parler à systemd (le programme qui gère les services) de l'hôte                         | ne suffit pas sans `--pid=host`                                         |
| `--cap-add=SYS_PTRACE`               | avoir le droit de regarder les autres processus, pour trouver celui de chaque connexion | ne suffit pas seul : les noms de processus manquent toujours            |
| `--security-opt apparmor=unconfined` | retirer une protection de Docker (AppArmor) qui bloque cette lecture                    | les noms de processus apparaissent, mais `systemctl` refuse de répondre |
| `-e SYSTEMD_IGNORE_CHROOT=1`         | forcer `systemctl` à répondre                                                           | les services sont de nouveau disponibles                                |

### Sécurité

Je n'ai pas utilisé `--privileged`, qui donne presque tous les droits de l'hôte au conteneur. J'ai donné les droits un par un, et chacun a un risque :

- `-v /:/host:ro` : le conteneur peut lire tous les fichiers de l'hôte. Le `:ro` l'empêche de les modifier.
- `--pid=host` et `SYS_PTRACE` : le conteneur peut observer tous les processus de l'hôte.
- `apparmor=unconfined` : retire une protection de Docker.
- `--network=host` : le conteneur utilise le même réseau que l'hôte.

### compose.yaml

Le fichier `compose.yaml` contient les mêmes options, écrites dans un fichier pour ne pas retaper la commande. Lancement : `docker compose run --rm audit`.

## 5. Conclusion

Le script récupère seize informations sans avoir besoin des droits root. Quand une information est inaccessible, il écrit une erreur et continue, sauf si une commande n'est pas installée. Dans Docker, un conteneur a son propre nom, son propre réseau, ses propres processus et ses propres fichiers, mais il utilise le noyau de l'hôte.
