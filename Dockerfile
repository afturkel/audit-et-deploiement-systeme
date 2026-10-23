# Image de l'outil d'audit, basée sur Debian 12
FROM debian:bookworm

# Installation de Ruby et des outils appelés par le script :
# ps (procps), ip et ss (iproute2), systemctl (systemd).
# Les deux options et le rm gardent l'image petite.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ruby procps iproute2 systemd \
    && rm -rf /var/lib/apt/lists/*

# Copie du script dans l'image
WORKDIR /app
COPY code/sae-audit.rb /app/sae-audit.rb

# Le conteneur lance toujours le script, avec les options données à docker run
ENTRYPOINT ["ruby", "/app/sae-audit.rb"]
