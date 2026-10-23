# sae-audit

Dépôt Git : https://github.com/afturkel/audit-et-deploiement-systeme

Cet outil regarde l'état d'un ordinateur Linux (Debian ou Ubuntu) et affiche le résultat. Il est écrit en Ruby. On peut aussi enregistrer le résultat dans un fichier JSON, ou le lancer dans Docker pour regarder l'ordinateur hôte (le vrai ordinateur qui contient Docker).

Le script `code/sae-audit.rb` récupère :

- nom de la machine, distribution (nom et version), version du noyau ;
- uptime, charge moyenne, mémoire et swap (utilisés et disponibles) ;
- interfaces réseau avec adresses MAC et IP (v4 et v6) ;
- connexions TCP et UDP (ports en écoute et connexions établies) avec le processus associé ;
- utilisateurs humains, en indiquant ceux qui sont connectés, et sessions en cours ;
- espace disque par partition ;
- les N processus qui consomment le plus de CPU et le plus de mémoire ;
- état des services (actif ou non, lancé au démarrage ou non).

Il marche sans droits administrateur (root). Quand une information n'est pas accessible, par exemple un fichier illisible ou une commande qui échoue, le script écrit une erreur à la place et continue avec le reste. Si une commande n'est pas installée (par exemple `ip`), le script s'arrête.

Aucun bonus du sujet n'a été fait.

Projet réalisé dans le cadre du BUT 3 Informatique - DACS.

## Prérequis

- Ruby 3 (bibliothèque standard seulement, aucune gem à installer).
- Les commandes `ip`, `ss`, `df`, `ps` et `systemctl` (paquets `iproute2`, `procps`, `systemd`).

## Utilisation

```
ruby code/sae-audit.rb [options]
```

| Option       | Rôle                                                                            | Défaut                       |
| ------------ | ------------------------------------------------------------------------------- | ---------------------------- |
| `-n N`       | nombre de processus affichés par critère (CPU et mémoire)                       | 5                            |
| `-s LISTE`   | services à vérifier, séparés par des virgules                                   | `ssh,ssh.socket,cron,docker` |
| `-r CHEMIN`  | racine sous laquelle lire les fichiers système (`/proc`, `/etc`, `/sys`...)     | `/`                          |
| `-j FICHIER` | enregistrer le résultat en JSON (avec la date et l'heure) au lieu de l'afficher | affichage à l'écran          |
| `-h`         | afficher l'aide                                                                 |                              |

Exemples :

```
ruby code/sae-audit.rb                          # affichage lisible
ruby code/sae-audit.rb -n 10                    # 10 processus par critère
ruby code/sae-audit.rb -s cron,nginx,docker     # choix des services
ruby code/sae-audit.rb -j audit.json            # sortie JSON dans un fichier
sudo ruby code/sae-audit.rb                     # avec root : processus de toutes les connexions
```

Extrait de l'affichage (les adresses, le nom de la machine et les identifiants sont des valeurs d'exemple, et la liste des connexions est raccourcie) :

```
> ruby code/sae-audit.rb

Audit système du 2026-03-12 14:22:07 (racine : /)

== nom_machine ==
  poste-demo

== version_kernel ==
  6.8.0-45-generic

== info_distro ==
  PRETTY_NAME : Ubuntu 26.04.1 LTS
  NAME : Ubuntu
  VERSION_ID : 26.04

== uptime ==
  0 j 5 h 12 min

== charge_moy ==
  1min : 0.74
  5min : 0.81
  15min : 0.90

== mem_swap_oct ==
  mem_total : 15.6 Go
  mem_disponible : 8.3 Go
  mem_utilisee : 7.3 Go
  swap_total : 4.0 Go
  swap_utilise : 2.5 Mo

== interfaces_reseau ==
  nom=docker0  etat=DOWN  mac=02:42:ac:14:00:01  adresses=inet 172.20.0.1
  nom=enp2s0  etat=DOWN  mac=00:1a:2b:3c:4d:5e  adresses=
  nom=lo  etat=UNKNOWN  mac=00:00:00:00:00:00  adresses=inet 127.0.0.1, inet6 ::1
  nom=wlp3s0  etat=UP  mac=00:1a:2b:6f:7a:8b  adresses=inet 192.168.0.23, inet6 fe80::21a:2bff:fe6f:7a8b

== connexions_reseau ==
  protocole=udp  etat=UNCONN  local=0.0.0.0:5353  distant=0.0.0.0:*  processus=chrome (pid 4120)
  protocole=udp  etat=UNCONN  local=127.0.0.53%lo:53  distant=0.0.0.0:*  processus=aucun ou non visible (droits requis)
  protocole=tcp  etat=LISTEN  local=127.0.0.1:631  distant=0.0.0.0:*  processus=aucun ou non visible (droits requis)
  protocole=tcp  etat=LISTEN  local=0.0.0.0:57621  distant=0.0.0.0:*  processus=spotify (pid 3977)
  protocole=tcp  etat=ESTAB  local=192.168.0.23:46538  distant=203.0.113.25:443  processus=firefox (pid 3811)
  protocole=tcp  etat=ESTAB  local=192.168.0.23:35768  distant=203.0.113.147:443  processus=code (pid 5230)

== uid_min ==
  1000

== uid_max ==
  60000

== utilisateurs_humains ==
  nom=alice  connecte=oui

== utilisateurs_connectes ==
  utilisateur=alice  depuis=2026-03-12 09:05:31  terminal=tty2

== espace_disque ==
  source=/dev/sda2  type=ext4  taille=233.4 Go  utilise=61.2 Go  disponible=160.1 Go  monte_sur=/
  source=/dev/sda1  type=vfat  taille=512.0 Mo  utilise=6.1 Mo  disponible=505.9 Mo  monte_sur=/boot/efi

== processus_cpu ==
  pid=4120  utilisateur=alice  cpu=14.2  memoire=2.4  commande=chrome
  pid=1873  utilisateur=alice  cpu=11.8  memoire=2.1  commande=gnome-shell
  pid=3811  utilisateur=alice  cpu=8.2  memoire=5.2  commande=firefox
  pid=5230  utilisateur=alice  cpu=6.7  memoire=3.1  commande=code
  pid=3977  utilisateur=alice  cpu=3.1  memoire=3.2  commande=spotify

== processus_memoire ==
  pid=3811  utilisateur=alice  cpu=8.2  memoire=5.2  commande=firefox
  pid=3977  utilisateur=alice  cpu=3.1  memoire=3.2  commande=spotify
  pid=5230  utilisateur=alice  cpu=6.7  memoire=3.1  commande=code
  pid=4120  utilisateur=alice  cpu=14.2  memoire=2.4  commande=chrome
  pid=1873  utilisateur=alice  cpu=11.8  memoire=2.1  commande=gnome-shell

== services ==
  service=ssh  etat=inactive  au_demarrage=not-found  note=-
  service=ssh.socket  etat=inactive  au_demarrage=not-found  note=-
  service=cron  etat=active  au_demarrage=enabled  note=-
  service=docker  etat=active  au_demarrage=enabled  note=-
```

Ici, `ssh` est `not-found` : le serveur SSH n'est pas installé sur cette machine.

Le fichier JSON contient une clé `date`, une clé `parametres` et une clé par information (`nom_machine`, `uptime`, `interfaces_reseau`, ...). En cas de problème, la valeur d'une information est de la forme `{ "erreur": "message" }`.

## Choix de conception

- Le script lit un fichier de `/proc`, `/sys` ou `/etc` quand il existe (nom de la machine, uptime, charge, mémoire, distribution, utilisateurs, sessions). C'est plus simple que de lancer une commande, et l'option `-r` peut changer le dossier de départ.
- Il lance une commande seulement quand il n'y a pas de fichier simple (`ip`, `ss`, `df`, `ps`, `systemctl`).
- Les utilisateurs humains sont ceux dont le numéro (UID) est compris entre `UID_MIN` et `UID_MAX` du fichier `/etc/login.defs`. Rien n'est écrit en dur, et `nobody` est écarté.
- Sous Ubuntu, `ssh` peut être inactif alors que `ssh.socket` répond : le script ajoute une note dans ce cas.
- La mémoire utilisée est calculée avec la mémoire « disponible » (`MemAvailable`) et non « libre », car la mémoire disponible compte aussi le cache que le système peut récupérer.

## Docker

### Construire l'image

```
docker build -t sae-audit .
```

L'image est basée sur Debian et contient Ruby, `procps`, `iproute2` et `systemd` (pour `systemctl`). Le point d'entrée est le script : les arguments de `docker run` lui sont transmis. Le `Dockerfile` est à la racine du dépôt.

### Lancer sans option

```
docker run --rm sae-audit
```

Le conteneur audite alors **lui-même**, pas la machine hôte :

| Information | Résultat dans le conteneur |
|---|---|
| nom de la machine | identifiant du conteneur |
| distribution | celle de l'image (Debian), pas celle de l'hôte |
| noyau, uptime, charge, mémoire | ceux de l'hôte, car le noyau est partagé |
| interfaces réseau | `eth0` et `lo` seulement |
| processus | ceux du conteneur seulement |
| utilisateurs | aucun humain |
| disque | le disque de l'hôte apparaît quand même |
| services | erreur : systemd n'est pas joignable |

### Auditer l'hôte

```
docker run --rm \
  --pid=host --network=host --uts=host \
  -v /:/host:ro -v /run/systemd:/run/systemd:ro \
  --cap-add=SYS_PTRACE --security-opt apparmor=unconfined \
  -e SYSTEMD_IGNORE_CHROOT=1 \
  sae-audit -r /host
```

ou, avec le fichier `compose.yaml` :

```
docker compose run --rm audit
```

Justification de chaque option :

| Option | Pourquoi | Risque |
|---|---|---|
| `--pid=host` | voir les processus de l'hôte, et permettre à `systemctl` de trouver systemd (le programme qui gère les services) | le conteneur voit tous les processus de l'hôte |
| `--network=host` | voir les interfaces et les connexions de l'hôte | le conteneur utilise le même réseau que l'hôte |
| `--uts=host` | voir le nom de la machine hôte | faible |
| `-v /:/host:ro` | lire `/etc`, `/proc` et `/sys` de l'hôte avec l'option `-r /host` | le conteneur peut lire tous les fichiers de l'hôte (sans les modifier) |
| `-v /run/systemd:/run/systemd:ro` | permettre à `systemctl` de parler au systemd de l'hôte | le conteneur peut lire l'état des services |
| `--cap-add=SYS_PTRACE` | avoir le droit de regarder les autres processus, pour trouver celui de chaque connexion (`ss -p`) | le conteneur peut observer les autres processus |
| `--security-opt apparmor=unconfined` | retirer une protection de Docker (AppArmor) qui bloque cette lecture, même avec `SYS_PTRACE` | une protection de Docker est retirée |
| `-e SYSTEMD_IGNORE_CHROOT=1` | sans la protection AppArmor, `systemctl` croit être dans un environnement isolé et refuse de répondre | aucun |

### Tester pas à pas

Toutes les commandes se lancent depuis le dossier du dépôt (celui qui contient le `Dockerfile`), sinon `docker build` répond `open Dockerfile: no such file or directory`.

1. Construire l'image : `docker build -t sae-audit .`
2. Lancer sans option : `docker run --rm sae-audit`, et observer la sortie ci-dessus.
3. Lancer la commande complète de la partie « Auditer l'hôte » et comparer : on retrouve le nom, la distribution, les interfaces, les utilisateurs et les services de l'hôte.
4. Ajouter **une seule** option à la fois et noter ce qui change : les résultats mesurés sont dans le tableau « Effet mesuré si on l'ajoute seule » du rapport (`rapport/rapport.md`).

5. Utiliser le fichier compose : `docker compose run --rm audit` (même résultat que la commande complète).

## Tests

Toutes les commandes se lancent depuis le dossier du dépôt.

### 1. Le script sur la machine

| Commande                                | Résultat attendu                                                                                           |
| --------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `ruby code/sae-audit.rb`                | 16 sections affichées                                                                                      |
| `ruby code/sae-audit.rb -n 3`           | 3 processus dans chaque liste de processus                                                                 |
| `ruby code/sae-audit.rb -s cron,docker` | seulement `cron` et `docker` dans les services                                                             |
| `ruby code/sae-audit.rb -j audit.json`  | message « Résultat enregistré dans audit.json » et un fichier JSON qui commence par `date` et `parametres` |

### 2. Les erreurs de commande

Le script s'arrête avec un message et le code 1, sans planter :

| Commande | Message attendu |
|---|---|
| `ruby code/sae-audit.rb -x` | `Erreur : option inconnue : -x (voir -h)` |
| `ruby code/sae-audit.rb -n` | `Erreur : l'option -n demande une valeur (voir -h)` |
| `ruby code/sae-audit.rb -n 0` | `Erreur : N doit être au moins 1` |
| `ruby code/sae-audit.rb -s "cd;ls"` | `Erreur : nom de service invalide : "cd;ls"` |

### 3. Sans root et avec root

```
ruby code/sae-audit.rb | grep -c "non visible"
sudo ruby code/sae-audit.rb | grep -c "non visible"
```

Ces commandes comptent les connexions dont le processus n'est pas visible : 13 sans root lors du test. Avec `sudo`, le nombre doit baisser, car root peut regarder tous les processus.

## Contenu du dépôt

```
code/sae-audit.rb   le script d'audit
Dockerfile          l'image Docker
compose.yaml        les options pour auditer l'hôte
rapport/rapport.md  le mini-rapport
```
