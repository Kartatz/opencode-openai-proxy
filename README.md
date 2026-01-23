# OpenCode API Container

Este repositório contém uma imagem Docker otimizada para hospedar o servidor do [OpenCode AI](https://opencode.ai), expondo sua API de forma segura e leve.

## 🚀 Como usar

### Via Docker Compose (Recomendado)

1. Crie um arquivo `.env` com suas credenciais:
   ```env
   OPENCODE_PASSWORD=sua_senha_segura
   ```

2. Suba o container:
   ```bash
   docker-compose up -d
   ```

A API estará disponível em `http://localhost:4096`.

### Via Docker Run

```bash
docker run -d \
  -p 4096:4096 \
  -e OPENCODE_SERVER_PASSWORD=sua_senha_segura \
  -v opencode_data:/home/node/.local/share/opencode \
  ghcr.io/seu-usuario/opencode-api:latest
```

## 🔒 Segurança

O servidor está configurado com Autenticação Básica HTTP.
- **Usuário padrão:** `opencode`
- **Senha:** Definida pela variável `OPENCODE_SERVER_PASSWORD`.

## 📂 Persistência

Para manter suas sessões e configurações após reiniciar o container, utilizamos volumes:
- `/home/node/.local/share/opencode`: Armazena banco de dados e sessões.
- `/home/node/.config/opencode`: Armazena configurações globais.

## 🛠️ Desenvolvimento

A imagem é baseada em `node:lts-slim`, garantindo um footprint reduzido e alta performance.

### Build Local
```bash
docker build -t opencode-api .
```

### Publicação Automática
Sempre que houver um push para a branch `main`, o GitHub Actions irá gerar uma nova imagem no GitHub Container Registry (GHCR).
