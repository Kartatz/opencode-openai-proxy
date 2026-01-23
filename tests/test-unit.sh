#!/bin/bash
set -e

echo "--- Rodando Testes Unitários (Mocks JS) ---"
cd proxy
npm install
npm test
cd ..
echo "--- Testes Unitários Concluídos com Sucesso! ---"
