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

# Check if we are running the default server command
if [[ "$1" == "opencode" && "$2" == "serve" ]]; then
    echo "Initializing OpenCode Super Mode (Server + Proxy)"
    
    # Start the OpenCode server in the background
    # We ensure it listens on 4097 (Internal)
    # The CMD in Dockerfile already sets --port 4097, so "$@" carries that.
    echo "Starting OpenCode Server on internal port 4097..."
    gosu node "$@" &
    SERVER_PID=$!
    
    # Wait for the server to be responsive
    echo "Waiting for OpenCode Server to become available..."
    MAX_RETRIES=30
    COUNT=0
    while ! curl -s http://127.0.0.1:4097/global/health > /dev/null; do
        if [ $COUNT -ge $MAX_RETRIES ]; then
            echo "Timeout waiting for OpenCode Server."
            kill $SERVER_PID
            exit 1
        fi
        
        # Check if process is still running
        if ! kill -0 $SERVER_PID 2>/dev/null; then
            echo "OpenCode Server process died unexpectedly."
            exit 1
        fi
        
        sleep 1
        COUNT=$((COUNT+1))
    done
    echo "OpenCode Server is up!"

    # Start the Proxy
    echo "Starting OpenAI Proxy on port 4096..."
    exec gosu node node /usr/src/proxy/index.js
else
    # Executa o comando passado para o container usando gosu para dropar privilégios de root
    exec gosu node "$@"
fi
