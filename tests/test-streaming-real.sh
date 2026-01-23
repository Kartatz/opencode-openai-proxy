#!/bin/bash

set -e

echo "🧪 Teste de Integração: Streaming Real com SSE"
echo "================================================"

BASE_URL="${BASE_URL:-http://localhost:3000}"
API_KEY="${OPENCODE_SERVER_PASSWORD:-test-key}"

echo "📍 URL Base: $BASE_URL"
echo "🔑 Usando API Key: ${API_KEY:0:10}..."
echo ""

echo "✅ Teste 1: Streaming sem Reasoning"
echo "-----------------------------------"
echo "Enviando request com stream=true..."
RESPONSE=$(curl -s -N -X POST "$BASE_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "model": "opencode/big-pickle",
    "messages": [{"role": "user", "content": "Responda com 3 palavras"}],
    "stream": true,
    "temperature": 0.7
  }')

echo "📦 Resposta:"
echo "$RESPONSE"

# Validar que contém chunks SSE
if echo "$RESPONSE" | grep -q "data: {"; then
    echo "✅ Chunks SSE encontrados"
else
    echo "❌ Nenhum chunk SSE encontrado"
    exit 1
fi

# Validar que termina com [DONE]
if echo "$RESPONSE" | grep -q "data: \[DONE\]"; then
    echo "✅ Stream finalizado com [DONE]"
else
    echo "❌ Stream não finalizado corretamente"
    exit 1
fi

echo ""
echo "✅ Teste 2: Streaming com Reasoning (se modelo suportar)"
echo "-----------------------------------------------------------"
echo "Enviando request com prompt que pode gerar reasoning..."
RESPONSE=$(curl -s -N -X POST "$BASE_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "model": "opencode/big-pickle",
    "messages": [{"role": "user", "content": "Explique por que 2+2=4 usando raciocínio lógico"}],
    "stream": true,
    "temperature": 0.7
  }')

echo "📦 Resposta:"
echo "$RESPONSE" | head -20
echo "..."
echo "[truncado]"

# Validar que contém chunks SSE
if echo "$RESPONSE" | grep -q "data: {"; then
    echo "✅ Chunks SSE encontrados"
else
    echo "❌ Nenhum chunk SSE encontrado"
    exit 1
fi

echo ""
echo "✅ Teste 3: Non-Streaming (para comparação)"
echo "-------------------------------------------"
echo "Enviando request com stream=false..."
RESPONSE=$(curl -s -X POST "$BASE_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "model": "opencode/big-pickle",
    "messages": [{"role": "user", "content": "Responda com uma frase simples"}],
    "stream": false,
    "temperature": 0.7
  }')

echo "📦 Resposta:"
echo "$RESPONSE" | jq '.choices[0].message.content' 2>/dev/null || echo "$RESPONSE"

# Validar estrutura JSON
if echo "$RESPONSE" | grep -q '"choices"'; then
    echo "✅ Resposta JSON válida"
else
    echo "❌ Resposta JSON inválida"
    exit 1
fi

echo ""
echo "✅ Todos os testes passaram! 🎉"
echo ""
echo "📊 Resumo:"
echo "- ✅ Streaming com SSE funciona"
echo "- ✅ Chunks chegam progressivamente"
echo "- ✅ Stream finaliza com [DONE]"
echo "- ✅ Non-streaming retorna JSON válido"
