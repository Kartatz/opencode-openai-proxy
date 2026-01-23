#!/bin/bash

# Define UID e GID padrões se não forem fornecidos
PUID=${PUID:-1000}
PGID=${PGID:-1000}

# Ajusta o GID do grupo node se necessário
if [ "$(id -g node)" -ne "$PGID" ]; then
    groupmod -o -g "$PGID" node
fi

# Ajusta o UID do usuário node se necessário
if [ "$(id -u node)" -ne "$PUID" ]; then
    usermod -o -u "$PUID" node
fi

# Garante que as pastas de configuração e dados pertencem ao usuário node
# Isso resolve o erro EACCES que você está recebendo
chown -R node:node /home/node/.local/share/opencode
chown -R node:node /home/node/.config/opencode
chown -R node:node /home/node/project

# Executa o comando passado para o container usando gosu para dropar privilégios de root
exec gosu node "$@"
