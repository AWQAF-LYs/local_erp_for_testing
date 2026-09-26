FROM frappe/bench:v5.31.0

USER root

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    git \
    python3-dev \
    python3-setuptools \
    python3-venv \
    virtualenv \
    nodejs \
    npm \
    xvfb \
    libfontconfig \
    wkhtmltopdf \
    supervisor \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g yarn

COPY init.sh /usr/local/bin/init.sh
COPY apps.txt /home/frappe/apps.txt
COPY backup.sh /home/frappe/backup.sh
COPY env.config /home/frappe/env.config

RUN chmod +x /usr/local/bin/init.sh \
    && chmod +x /home/frappe/backup.sh \
    && chown -R frappe:frappe /home/frappe

USER frappe

WORKDIR /home/frappe

ENTRYPOINT ["/usr/local/bin/init.sh"]
