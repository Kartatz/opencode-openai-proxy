#!/bin/bash
set -e

IMAGE_NAME="opencode-integration-test-$(date +%s)"
CONTAINER_NAME="opencode-test-container"
PASSWORD="test-password-123"

echo "--- Iniciando Teste de Integração (Docker) ---"

# 1. Build
echo "1. Buildando imagem: $IMAGE_NAME..."
docker build -t "$IMAGE_NAME" .

# 2. Run
echo "2. Iniciando container..."
docker run -d --name "$CONTAINER_NAME" \
  -e OPENCODE_SERVER_PASSWORD="$PASSWORD" \
  -p 4096:4096 \
  -p 4097:4097 \
  "$IMAGE_NAME"

# 3. Wait for Ready
echo "3. Aguardando inicialização (pode levar até 30s)..."
MAX_RETRIES=30
COUNT=0
until curl -s http://localhost:4096/health | grep -q "ok"; do
    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo "Erro: Timeout na inicialização do Proxy."
        docker logs "$CONTAINER_NAME"
        docker stop "$CONTAINER_NAME"
        docker rm "$CONTAINER_NAME"
        docker rmi "$IMAGE_NAME"
        exit 1
    fi
    sleep 1
    COUNT=$((COUNT+1))
done
echo "Proxy está online!"

# 4. Test Models
echo "4. Testando GET /v1/models..."
MODELS_RES=$(curl -s http://localhost:4096/v1/models -H "Authorization: Bearer $PASSWORD")
echo "Modelos Disponíveis: $MODELS_RES"

if echo "$MODELS_RES" | grep -q "object\":\"list"; then
    echo "Sucesso: Listagem de modelos OK"
else
    echo "Erro: Resposta de modelos inválida: $MODELS_RES"
    # Falha mas continua para limpeza
fi

# Extrair dinamicamente o primeiro modelo para os próximos testes
TEST_MODEL=$(echo "$MODELS_RES" | jq -r '.data[0].id')
echo "Usando modelo para testes: $TEST_MODEL"

# 5. Test Completion
echo "5. Testando POST /v1/chat/completions (No Stream)..."
COMPLETION_RES=$(curl -s -X POST http://localhost:4096/v1/chat/completions \
  -H "Authorization: Bearer $PASSWORD" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$TEST_MODEL\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Olá\"}]
  }")

echo "Resposta: $COMPLETION_RES"

if echo "$COMPLETION_RES" | grep -q "chat.completion"; then
    echo "Sucesso: Chat Completion OK"
else
    echo "Erro: Chat Completion falhou"
fi

# 6. Test Streaming Completion
echo "6. Testando POST /v1/chat/completions (With Stream)..."
echo "--- Inicio do Stream ---"
STREAM_RES=$(curl -s -N -X POST http://localhost:4096/v1/chat/completions \
  -H "Authorization: Bearer $PASSWORD" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$TEST_MODEL\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Diga apenas: Stream OK\"}],
    \"stream\": true
  }")

echo "$STREAM_RES"
echo "--- Fim do Stream ---"

if echo "$STREAM_RES" | grep -q "data: \[DONE\]"; then
    echo "Sucesso: Chat Completion Stream OK"
else
    echo "Erro: Chat Completion Stream falhou ou incompleto"
fi

# 7. Cleanup
echo "7. Limpando recursos..."
docker stop "$CONTAINER_NAME"
docker rm "$CONTAINER_NAME"
docker rmi "$IMAGE_NAME"

echo "--- Teste de Integração Concluído! ---"
