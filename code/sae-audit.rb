#!/usr/bin/env ruby
# Audit d'un système Linux (Debian et Ubuntu).
# Chaque méthode récupère une information et renvoie un Hash.
# En cas de problème, elle renvoie { clé => { erreur: "..." } } : le script continue.
# Pas besoin d'être root : ce qui n'est pas accessible est signalé.
#
# Usage : ruby sae-audit.rb [-n N] [-s service,service] [-r RACINE] [-j FICHIER]

# Chargement de la bibliothèque qui sait lire et écrire du JSON
require 'json'

# Valeurs par défaut, utilisées quand l'option n'est pas donnée
# (les variables qui commencent par $ sont visibles partout, y compris dans les méthodes)
$racine = "/"
$n = 5
$services = ["ssh", "ssh.socket", "cron", "docker"]
$fichier_json = nil

# ARGV contient les mots tapés après le nom du script : ["-n", "3", "-r", "/host"].
# On le parcourt deux cases par deux cases : l'option, puis sa valeur.
i = 0
while i < ARGV.size
  option = ARGV[i]
  # La valeur est le mot suivant (par exemple "3"), ou nil s'il n'y en a pas
  valeur = ARGV[i + 1]
  if option == "-h"
    # -h : affichage de l'aide, puis arrêt du script sans erreur
    puts "Usage : ruby sae-audit.rb [options]"
    puts "  -n N          nombre de processus par critère (défaut 5)"
    puts "  -s LISTE      services à vérifier, séparés par des virgules"
    puts "  -r CHEMIN     racine des fichiers système (défaut /)"
    puts "  -j FICHIER    enregistrer le résultat en JSON, avec la date"
    puts "  -h            afficher cette aide"
    exit
  elsif option != "-n" && option != "-s" && option != "-r" && option != "-j"
    # Option inconnue : message, puis arrêt avec le code 1 (échec)
    puts "Erreur : option inconnue : #{option} (voir -h)"
    exit 1
  elsif valeur.nil?
    puts "Erreur : l'option #{option} demande une valeur (voir -h)"
    exit 1
  elsif option == "-n"
    # to_i transforme le texte en nombre entier
    $n = valeur.to_i
  elsif option == "-s"
    # split coupe le texte à chaque virgule
    $services = valeur.split(",")
  elsif option == "-r"
    $racine = valeur
  else
    # Sinon c'est -j : nom du fichier JSON
    $fichier_json = valeur
  end
  # On avance de deux cases : l'option et sa valeur
  i += 2
end

# Vérification de N : -n 0, -n -2 et -n abc (qui donne 0) sont refusés
if $n < 1
  puts "Erreur : N doit être au moins 1"
  exit 1
end

# Refuse les noms de services avec des caractères dangereux (comme ";"),
# car ils sont passés à une commande.
$services.each do |nom|
  # Le nom doit contenir seulement des lettres, chiffres et . _ @ : -
  if nom !~ /\A[A-Za-z0-9._@:-]+\z/
    puts "Erreur : nom de service invalide : #{nom.inspect}"
    exit 1
  end
end

# Dossier où chercher les fichiers système : "/" ou "/host" dans Docker
# (une constante, en majuscules, est visible dans les méthodes)
RACINE = $racine

# Une ligne de /etc/passwd : nom:x:UID:GID:commentaire:dossier:shell avec $1 = nom, $2 = UID
# ([^:]+) = un ou plusieurs caractères qui ne sont pas ":", (\d+) = des chiffres
REGEX_PSWD = /^([^:]+):[^:]*:(\d+):\d+:[^:]*:[^:]+:[^:]+$/

# Renvoie l'erreur si le fichier n'est pas lisible et nil (rien) s'il est lisible : la méthode peut alors continuer.
def fichier_illisible(cle, fichier)
  if !File.readable?(fichier)
    { cle => { erreur: "fichier absent ou illisible : #{fichier}" } }
  end
end

# Nom de la machine, lu dans /proc/sys/kernel/hostname.
def nom_machine
  # File.join colle les morceaux du chemin avec un / entre eux
  fichier = File.join(RACINE, "/proc/sys/kernel/hostname")
  # Fichier illisible : erreur contient le Hash d'erreur et return arrête la méthode. Sinon erreur vaut nil (donc faux) et la méthode continue.
  erreur = fichier_illisible(:nom_machine, fichier)
  return erreur if erreur
  { nom_machine: IO.readlines(fichier)[0].strip }
end

# Version du noyau, lue dans /proc/sys/kernel/osrelease.
def version_kernel
  fichier = File.join(RACINE, "/proc/sys/kernel/osrelease")
  erreur = fichier_illisible(:version_kernel, fichier)
  return erreur if erreur
  { version_kernel: IO.readlines(fichier)[0].strip }
end

# Distribution (nom et version), lue dans /etc/os-release. On garde trois lignes : PRETTY_NAME, NAME et VERSION_ID.
def info_distro
  fichier = File.join(RACINE, "/etc/os-release")
  erreur = fichier_illisible(:info_distro, fichier)
  return erreur if erreur
  distro = {}
  IO.readlines(fichier).each do |ligne|
    # Récupération des clés et valeurs à l'aide d'une regex
    if ligne =~ /^(PRETTY_NAME|NAME|VERSION_ID)="?([^"]*)"?$/
      cle, valeur = $1, $2
      distro[cle] = valeur
    end
  end
  { info_distro: distro }
end

# Temps écoulé depuis le démarrage, en secondes (premier nombre de /proc/uptime).
def uptime
  fichier = File.join(RACINE, "/proc/uptime")
  erreur = fichier_illisible(:uptime, fichier)
  return erreur if erreur
  { uptime: IO.readlines(fichier)[0].split[0].to_f }
end

# Charge moyenne sur 1, 5 et 15 minutes (trois premiers nombres de /proc/loadavg).
def charge_moy
  fichier = File.join(RACINE, "/proc/loadavg")
  erreur = fichier_illisible(:charge_moy, fichier)
  return erreur if erreur
  champs = IO.readlines(fichier)[0].split
  { charge_moy: { "1min" => champs[0].to_f, "5min" => champs[1].to_f, "15min" => champs[2].to_f } }
end

# Mémoire et swap en octets, lus dans /proc/meminfo (les valeurs y sont en kB).
# Mémoire utilisée = total - disponible.
def mem_swap_oct
  fichier = File.join(RACINE, "/proc/meminfo")
  erreur = fichier_illisible(:mem_swap_oct, fichier)
  return erreur if erreur
  # Hash nom => valeur. Il s'appelle kb car le fichier est en kB, mais il contiendra des octets
  kb = {}
  IO.readlines(fichier).each do |ligne|
    # Sélection des lignes de la forme "Nom: nombre"
    if ligne =~ /^(\w+):\s+(\d+)/
      cle, valeur = $1, $2.to_i
      # Conversion de kB en octets (1 kB = 1024 octets)
      kb[cle] = valeur * 1024
    end
  end
  # Vérification que les quatre valeurs nécessaires aux calculs ont bien été trouvées
  if kb["MemTotal"].nil? || kb["MemAvailable"].nil? || kb["SwapTotal"].nil? || kb["SwapFree"].nil?
    { mem_swap_oct: { erreur: "champs manquants dans #{fichier}" } }
  else
    # "disponible" et pas "libre" car il compte aussi le cache que le système peut récupérer
    { mem_swap_oct: {
      mem_total: kb["MemTotal"],
      mem_disponible: kb["MemAvailable"],
      mem_utilisee: kb["MemTotal"] - kb["MemAvailable"],
      swap_total: kb["SwapTotal"],
      swap_utilise: kb["SwapTotal"] - kb["SwapFree"]
    } }
  end
end

# Interfaces réseau avec leur adresse MAC et leurs adresses IP (v4 et v6).
# La MAC et l'état sont lus dans /sys/class/net, les adresses IP viennent de
# la commande `ip -o addr` (une ligne par adresse).
def interfaces_reseau
  # Un sous-dossier de ce dossier par interface
  dossier = File.join(RACINE, "/sys/class/net")
  return { interfaces_reseau: { erreur: "dossier absent : #{dossier}" } } if !File.directory?(dossier)
  # Les accents graves lancent la commande et renvoient sa sortie
  sortie = `ip -o addr`
  # Code de retour de la commande (0 = elle a réussi)
  code = $?.exitstatus
  return { interfaces_reseau: { erreur: "ip -o addr : code #{code} (#{sortie.strip})" } } if code != 0
  # Hash nom d'interface => liste de ses adresses
  ips = {}
  sortie.lines.each do |ligne|
    # Lignes de la forme "3: wlp3s0    inet 10.0.0.2/24 ..."
    if ligne =~ /^\d+:\s+(\S+)\s+(inet6?)\s+([^\s\/]+)/
      # famille : inet = IPv4, inet6 = IPv6
      # Certaines interfaces virtuelles s'écrivent "veth12@if4" : on garde le nom avant le @
      nom, famille, adresse = $1.split("@")[0], $2, $3
      ips[nom] = [] if ips[nom].nil?
      ips[nom] << { famille: famille, adresse: adresse }
    end
  end
  interfaces = []
  Dir.glob(File.join(dossier, "*")).sort.each do |chemin|
    # basename garde le dernier morceau du chemin : /sys/class/net/wlp3s0 => wlp3s0
    nom = File.basename(chemin)
    # État (up, down...) et MAC. Forme : condition ? valeur_si_vrai : valeur_si_faux
    # "inconnu" si le fichier est illisible
    fichier_etat = File.join(chemin, "operstate")
    etat = File.readable?(fichier_etat) ? IO.readlines(fichier_etat)[0].strip.upcase : "inconnu"
    fichier_mac = File.join(chemin, "address")
    mac = File.readable?(fichier_mac) ? IO.readlines(fichier_mac)[0].strip : "inconnu"
    # Liste vide si l'interface n'a pas d'adresse IP
    adresses = ips[nom]
    adresses = [] if adresses.nil?
    interfaces << { nom: nom, etat: etat, mac: mac, adresses: adresses }
  end
  { interfaces_reseau: interfaces }
end

# Connexions TCP et UDP (ports en écoute et connexions établies) avec leur processus.
# Utilise la commande `ss`. Sans root, on ne voit que les processus de l'utilisateur qui lance le script.
def connexions_reseau
  sortie = `ss -H -tunap`
  code = $?.exitstatus
  if code != 0
    { connexions_reseau: { erreur: "ss : code #{code} (#{sortie.strip})" } }
  else
    connexions = []
    sortie.lines.each do |ligne|
      # Découpage en 7 morceaux au maximum, séparés par des espaces
      morceaux = ligne.split(" ", 7)
      # On garde seulement les ports en écoute (LISTEN, UNCONN) et les connexions établies (ESTAB)
      next unless ["LISTEN", "UNCONN", "ESTAB"].include?(morceaux[1])
      # Sans le 7e champ, le processus n'est pas visible (sans root, ou sans les droits
      # nécessaires dans Docker) ou n'existe pas
      processus = "aucun ou non visible (droits requis)"
      if morceaux[6] && morceaux[6] =~ /\(\("([^"]+)",pid=(\d+)/
        nom, pid = $1, $2
        processus = "#{nom} (pid #{pid})"
      end
      connexions << {
        protocole: morceaux[0],
        etat: morceaux[1],
        local: morceaux[4],
        distant: morceaux[5],
        processus: processus
      }
    end
    { connexions_reseau: connexions }
  end
end

# Cherche UID_MIN ou UID_MAX dans /etc/login.defs : ce sont les limites des
# numéros d'utilisateur des humains.
def uid_limite(nom)
  # "UID_MIN" devient le symbole :uid_min (downcase met en minuscules, to_sym fait un symbole)
  cle = nom.downcase.to_sym
  fichier = File.join(RACINE, "/etc/login.defs")
  erreur = fichier_illisible(cle, fichier)
  return erreur if erreur
  # nil (rien) tant qu'on n'a pas trouvé la ligne
  valeur = nil
  IO.readlines(fichier).each do |ligne|
    # Ligne qui commence par le nom, suivi d'espaces, puis d'un nombre
    # (le ^ évite de confondre UID_MIN avec SYS_UID_MIN ou SUB_UID_MIN)
    if ligne =~ /^#{nom}\s+(\d+)/
      # "1000" devient 1000
      valeur = $1.to_i
    end
  end
  if valeur.nil?
    { cle => { erreur: "#{nom} introuvable dans #{fichier}" } }
  else
    { cle => valeur }
  end
end

# Utilisateurs humains : les comptes de /etc/passwd dont le numéro est entre
# UID_MIN et UID_MAX. Chacun est marqué connecté (oui ou non).
def utilisateurs_humains
  # uid_limite renvoie un Hash, [:clé] en extrait le nombre
  min = uid_limite("UID_MIN")[:uid_min]
  max = uid_limite("UID_MAX")[:uid_max]
  # Si l'une des limites est une erreur, ce n'est pas un nombre
  return { utilisateurs_humains: { erreur: "plage d'UID inconnue" } } if !min.is_a?(Integer) || !max.is_a?(Integer)
  fichier = File.join(RACINE, "/etc/passwd")
  erreur = fichier_illisible(:utilisateurs_humains, fichier)
  return erreur if erreur
  # Liste des sessions (ou une erreur si elle est inconnue)
  connectes = utilisateurs_connectes[:utilisateurs_connectes]
  humains = []
  IO.readlines(fichier).each do |ligne|
    # Lignes qui ont la forme d'un compte, grâce à la regex REGEX_PSWD
    if ligne =~ REGEX_PSWD
      nom, uid = $1, $2.to_i
      # On garde seulement la plage des humains (cela écarte root, les comptes système et nobody)
      if uid >= min && uid <= max
        # "inconnu" si on n'a pas pu lire les sessions
        etat = "inconnu"
        if connectes.is_a?(Array)
          etat = "non"
          # Si une session est à ce nom, la personne est connectée
          connectes.each do |session|
            etat = "oui" if session[:utilisateur] == nom
          end
        end
        humains << { nom: nom, connecte: etat }
      end
    end
  end
  { utilisateurs_humains: humains }
end

# Utilisateurs connectés en ce moment, d'après les fichiers de session de
# /run/systemd/sessions/ (un fichier par session).
def utilisateurs_connectes
  dossier = File.join(RACINE, "/run/systemd/sessions")
  return { utilisateurs_connectes: { erreur: "dossier absent : #{dossier}" } } if !File.directory?(dossier)
  connectes = []
  # Dir.glob donne la liste des chemins des fichiers du dossier
  Dir.glob(File.join(dossier, "*")).each do |fichier|
    next unless File.readable?(fichier)
    # Informations de cette session (clé => valeur)
    session = {}
    IO.readlines(fichier).each do |ligne|
      # Chaque ligne est de la forme CLE=valeur
      if ligne =~ /^(\w+)=(.*)$/
        cle, valeur = $1, $2
        session[cle] = valeur
      end
    end
    # On garde seulement les vraies sessions d'utilisateur
    # (CLASS=manager est la session interne de systemd, ce n'est pas une personne)
    next unless session["CLASS"] == "user"
    # REALTIME est en microsecondes depuis 1970 : on divise par 1 000 000 pour avoir
    # des secondes, puis on met en forme "2026-10-21 12:12:10"
    depuis = Time.at(session["REALTIME"].to_i / 1_000_000).strftime("%F %T")
    connectes << { utilisateur: session["USER"], depuis: depuis, terminal: session["TTY"] }
  end
  { utilisateurs_connectes: connectes }
end

# Espace disque de chaque partition (taille, utilisé, disponible), en octets.
# Utilise la commande `df` et ignore les systèmes de fichiers virtuels.
def espace_disque
  # --output choisit les colonnes, -B1 donne les tailles en octets, -x exclut un type
  # de système de fichiers (ici les types virtuels, qui ne sont pas de vrais disques)
  sortie = `LC_ALL=C df --output=source,fstype,size,used,avail,target -B1 -x tmpfs -x devtmpfs -x efivarfs -x squashfs -x overlay`
  code = $?.exitstatus
  if code != 0
    { espace_disque: { erreur: "df : code #{code} (#{sortie.strip})" } }
  else
    partitions = []
    # each_with_index donne aussi le numéro i de la ligne
    sortie.lines.each_with_index do |ligne, i|
      next if i == 0                   # saute la ligne numéro 0 (l'en-tête)
      # 6 colonnes : le point de montage reste entier
      source, type, taille, utilise, disponible, monte_sur = ligne.split(" ", 6)
      partitions << { source: source, type: type, taille: taille.to_i, utilise: utilise.to_i,
                      disponible: disponible.to_i, monte_sur: monte_sur.strip }
    end
    { espace_disque: partitions }
  end
end

# Les N processus qui consomment le plus, triés par critère (pcpu ou pmem).
# Utilise la commande `ps`.
def top_processus(cle, critere)
  # -e tous les processus, -o choisit les colonnes, --sort=-critère trie du plus grand
  # au plus petit (le - inverse l'ordre), --no-headers retire la ligne d'en-tête
  sortie = `ps -eo pid,user,pcpu,pmem,comm --sort=-#{critere} --no-headers`
  code = $?.exitstatus
  if code != 0
    { cle => { erreur: "ps : code #{code} (#{sortie.strip})" } }
  else
    processus = []
    # first($n) garde les N premières lignes, déjà triées par la commande
    sortie.lines.first($n).each do |ligne|
      # 5 morceaux au maximum : le nom de la commande peut contenir des espaces
      pid, utilisateur, cpu, memoire, commande = ligne.split(" ", 5)
      processus << { pid: pid.to_i, utilisateur: utilisateur, cpu: cpu.to_f,
                     memoire: memoire.to_f, commande: commande.strip }
    end
    { cle => processus }
  end
end

# Pour chaque service demandé : est-il actif, et est-il lancé au démarrage ?
# Utilise `systemctl is-active` et `systemctl is-enabled`.
def services
  liste = []
  # Services demandés (option -s, ou la liste par défaut)
  $services.each do |nom|
    # L'état (active, inactive, failed...) est lu sur la sortie de la commande
    # (le code de retour n'est pas utilisé : il n'est pas 0 pour un service inactif)
    actif = `systemctl is-active #{nom} 2>/dev/null`.strip
    code = $?.exitstatus
    # Sortie vide : systemctl est absent ou systemd n'est pas démarré (cas d'un conteneur)
    return { services: { erreur: "systemctl indisponible pour #{nom} (code #{code})" } } if actif.empty?
    # enabled, disabled...
    demarrage = `systemctl is-enabled #{nom} 2>/dev/null`.strip
    # ssh inactif ne veut pas dire que le serveur ne répond pas : ssh.socket peut
    # le lancer à la première connexion.
    note = nil
    if nom == "ssh" && actif != "active"
      socket = `systemctl is-active ssh.socket 2>/dev/null`.strip
      note = "répond quand même via ssh.socket" if socket == "active"
    end
    liste << { service: nom, etat: actif, au_demarrage: demarrage, note: note }
  end
  { services: liste }
end

# Rassemble toutes les informations dans un seul Hash.
def audit
  resultat = {}
  # Chaque méthode renvoie un Hash à une clé : merge! l'ajoute au résultat
  [nom_machine, version_kernel, info_distro, uptime, charge_moy, mem_swap_oct,
   interfaces_reseau, connexions_reseau, uid_limite("UID_MIN"), uid_limite("UID_MAX"),
   utilisateurs_humains, utilisateurs_connectes, espace_disque,
   top_processus(:processus_cpu, "pcpu"), top_processus(:processus_memoire, "pmem"),
   services].each do |info|
    resultat.merge!(info)
  end
  resultat
end

# Transforme un nombre d'octets en Ko, Mo, Go...
def octets_lisibles(octets)
  unites = ["o", "Ko", "Mo", "Go", "To"]
  # Float pour pouvoir diviser avec des virgules
  valeur = octets.to_f
  # i est la position de l'unité dans la liste (0 = octets)
  i = 0
  # Tant que la valeur dépasse 1024 et qu'il reste une unité plus grande,
  # on divise par 1024 et on passe à l'unité suivante
  while valeur >= 1024 && i < unites.size - 1
    valeur = valeur / 1024
    i += 1
  end
  # Un chiffre après la virgule, puis l'unité (par exemple "14.5 Go")
  "#{format('%.1f', valeur)} #{unites[i]}"
end

# Transforme des secondes en jours, heures et minutes.
def duree_lisible(secondes)
  total = secondes.to_i
  # 86400 secondes = 1 jour, 3600 = 1 heure, 60 = 1 minute
  # (/ donne le quotient de la division, % donne le reste)
  "#{total / 86400} j #{(total % 86400) / 3600} h #{(total % 3600) / 60} min"
end

# Met en forme une valeur selon son nom : octets lisibles, "-" si vide, adresses d'une interface.
def formater(cle, valeur)
  if valeur.nil?
    "-"
  elsif valeur.is_a?(Integer) && cle.to_s =~ /taille|utilise|disponible|\Amem_|\Aswap_/
    # Nombre entier dont le nom parle d'octets (les % de CPU sont décimaux,
    # \A = début du texte, pour écarter la colonne memoire des processus)
    octets_lisibles(valeur)
  elsif valeur.is_a?(Array)
    # Liste d'adresses d'une interface : "inet 10.0.0.2, inet6 ::1"
    morceaux = []
    valeur.each do |adresse|
      morceaux << "#{adresse[:famille]} #{adresse[:adresse]}"
    end
    morceaux.join(", ")
  else
    valeur.to_s
  end
end

# Affiche une valeur selon son type : Hash, liste vide, liste de Hash ou texte.
def afficher_valeur(valeur)
  if valeur.is_a?(Hash)
    # Une ligne "clé : valeur" par clé
    valeur.each do |cle, v|
      puts "  #{cle} : #{formater(cle, v)}"
    end
  elsif valeur.is_a?(Array) && valeur.empty?
    puts "  (aucun)"
  elsif valeur.is_a?(Array)
    # Liste de Hash : une ligne par élément, de la forme "clé=valeur  clé=valeur"
    valeur.each do |element|
      champs = []
      element.each do |cle, v|
        champs << "#{cle}=#{formater(cle, v)}"
      end
      puts "  " + champs.join("  ")
    end
  else
    puts "  #{valeur}"
  end
end

# Affiche tout le résultat, une section par information.
def afficher(resultat)
  puts "Audit système du #{resultat[:date]} (racine : #{RACINE})"
  resultat.each do |cle, valeur|
    # La date et les paramètres sont déjà utilisés dans le titre
    next if cle == :date || cle == :parametres
    puts "\n== #{cle} =="
    if cle == :uptime && valeur.is_a?(Float)
      puts "  #{duree_lisible(valeur)}"
    else
      afficher_valeur(valeur)
    end
  end
end

# Le résultat commence par la date et les paramètres, puis toutes les informations
resultat = {
  date: Time.now.strftime("%F %T"),
  parametres: { racine: RACINE, n: $n, services: $services }
}
resultat.merge!(audit)

# Sans -j : affichage à l'écran. Avec -j : enregistrement dans un fichier JSON.
if $fichier_json.nil?
  afficher(resultat)
else
  fichier = $fichier_json
  # Vérification qu'on peut écrire : le fichier s'il existe déjà, sinon son dossier
  if File.exist?(fichier) ? File.writable?(fichier) : File.writable?(File.dirname(fichier))
    # "w" efface le contenu du fichier s'il existait
    File.open(fichier, "w") do |f|
      # pretty_generate ajoute des retours à la ligne et des indentations
      f.puts JSON.pretty_generate(resultat)
    end
    puts "Résultat enregistré dans #{fichier}"
  else
    puts "Erreur : impossible d'écrire dans #{fichier}"
    exit 1
  end
end
