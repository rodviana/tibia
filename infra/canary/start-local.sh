#!/usr/bin/env bash
# Entrada da stack (infra/docker-compose.yml): delega no bootstrap da imagem.
set -euo pipefail
cd /canary
exec bash /canary/start.sh
