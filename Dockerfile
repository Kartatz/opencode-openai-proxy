# Use Node.js LTS Slim como base (Debian-based, leve e compatível)
FROM node:lts-slim

# Instala dependências mínimas necessárias para o OpenCode, Git e suporte a PUID/PGID
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    && dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')" \
    && curl -Lo /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/1.17/gosu-$dpkgArch" \
    && chmod +x /usr/local/bin/gosu \
    && gosu --version \
    && rm -rf /var/lib/apt/lists/*

# Instala o OpenCode globalmente via NPM
RUN npm install -g opencode-ai

# Cria diretórios para persistência de dados e config
RUN mkdir -p /home/node/.local/share/opencode \
    && mkdir -p /home/node/.config/opencode \
    && mkdir -p /home/node/project \
    && chown -R node:node /home/node

# Copia e configura o script de entrada
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Define o diretório de trabalho
WORKDIR /home/node/project

# Setup Proxy
COPY proxy /usr/src/proxy
RUN cd /usr/src/proxy && npm install

# Expõe a porta padrão (agora servida pelo Proxy)
EXPOSE 4096

# Variáveis de ambiente
# O servidor OpenCode rodará na 4097 internamente
ENV OPENCODE_SERVER_HOSTNAME=0.0.0.0
ENV OPENCODE_SERVER_PORT=4097

# Define o script de entrada
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Comando padrão
CMD ["opencode", "serve", "--hostname", "0.0.0.0", "--port", "4097"]
