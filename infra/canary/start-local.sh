#!/usr/bin/env bash
# Usado por infra/docker-compose.yml (serviço server). Delega no bootstrap oficial
# embebido na imagem (/canary/start.sh: espera pelo MySQL, schema, config.lua, canary).
set -euo pipefail
cd /canary
exec bash /canary/start.sh
