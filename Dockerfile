# Use Node.js LTS Slim como base (Debian-based, leve e compatível)
FROM node:lts-slim

# Instala dependências mínimas necessárias para o OpenCode e Git
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Instala o OpenCode globalmente via NPM
RUN npm install -g opencode-ai

# Cria diretórios para persistência de dados e config
RUN mkdir -p /home/node/.local/share/opencode \
    && mkdir -p /home/node/.config/opencode \
    && mkdir -p /home/node/project \
    && chown -R node:node /home/node

# Define o usuário node para segurança
USER node
WORKDIR /home/node/project

# Expõe a porta padrão da API do OpenCode
EXPOSE 4096

# Variáveis de ambiente padrão para o servidor
ENV OPENCODE_SERVER_HOSTNAME=0.0.0.0
ENV OPENCODE_SERVER_PORT=4096

# Comando para iniciar o servidor
# Aceita OPENCODE_SERVER_PASSWORD e OPENCODE_SERVER_USERNAME via env
CMD ["opencode", "serve", "--hostname", "0.0.0.0", "--port", "4096"]
