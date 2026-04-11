#!/usr/bin/env bash
# Para o Compose e remove contentores/rede — **não** apaga volumes nomeados (ex.: dados MySQL).
# Uso: a partir da raiz do repo: ./infra/down-keep-volumes.sh
#
# Depois podes apagar a pasta do clone e voltar a clonar; os volumes Docker ficam na máquina.
# Antes de apagar o repo, copia os teus secrets: infra/mysql/.env infra/canary/.env infra/otserver-web/.env
#
set -euo pipefail

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$INFRA_DIR/.." && pwd)"
cd "$ROOT"

compose() {
	if docker compose version &>/dev/null; then
		docker compose -f infra/docker-compose.yml "$@"
	elif sudo docker compose version &>/dev/null; then
		sudo docker compose -f infra/docker-compose.yml "$@"
	else
		echo "[down] Erro: Docker Compose v2 em falta." >&2
		exit 1
	fi
}

echo "[down] docker compose down (sem -v — volumes mantidos)..."
compose down --remove-orphans

echo "[down] Feito. Volumes deste projecto (nome típico ot-stack_*):"
docker volume ls 2>/dev/null | grep -E 'ot-stack|NAME' || true

cat <<'EOF'

Próximos passos (refazer clone, manter base no Docker):
  1) Backup dos .env (ficheiros com nomes diferentes):
       mkdir -p ~/ot-env-backup
       cp infra/mysql/.env ~/ot-env-backup/mysql.env
       cp infra/canary/.env ~/ot-env-backup/canary.env
       cp infra/otserver-web/.env ~/ot-env-backup/otserver-web.env
  2) cd .. && rm -rf tibia
  3) git clone --recurse-submodules https://github.com/rodviana/tibia.git tibia && cd tibia
  4) cp ~/ot-env-backup/mysql.env infra/mysql/.env
       cp ~/ot-env-backup/canary.env infra/canary/.env
       cp ~/ot-env-backup/otserver-web.env infra/otserver-web/.env
  5) ./infra/up.sh --public-ip

Não uses "docker compose down -v" se quiseres manter a base de dados.
EOF
