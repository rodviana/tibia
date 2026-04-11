#!/usr/bin/env bash
# Atualiza código (git + submódulos), puxa imagens, dá down na stack e volta a subir com up.sh.
# Uso na EC2 (na raiz do repo ou de qualquer sítio):
#   ./infra/stack-refresh.sh
#   ./infra/stack-refresh.sh --no-public-ip
#   ./infra/stack-refresh.sh --wipe-volumes   # APAGA volume MySQL (personagens / DB)
#   ./infra/stack-refresh.sh --skip-git       # só Docker (sem pull)
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
    echo "[refresh] Erro: Docker Compose v2 em falta (newgrp docker ou sudo)." >&2
    exit 1
  fi
}

PUBLIC_IP=1
WIPE_VOLUMES=0
SKIP_GIT=0
PINNED_SUBMODULES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-public-ip) PUBLIC_IP=0; shift ;;
    --wipe-volumes)
      WIPE_VOLUMES=1
      shift
      ;;
    --skip-git) SKIP_GIT=1; shift ;;
    --pinned-submodules)
      PINNED_SUBMODULES=1
      shift
      ;;
    -h|--help)
      cat <<'EOF'
  ./infra/stack-refresh.sh              # git pull + submódulos (último main/master) + Docker + up
  ./infra/stack-refresh.sh --no-public-ip
  ./infra/stack-refresh.sh --wipe-volumes   # down -v (apaga dados MySQL no volume Docker)
  ./infra/stack-refresh.sh --skip-git       # sem git; só imagens + down + up
  ./infra/stack-refresh.sh --pinned-submodules   # submódulos só no commit que o repo pai fixa (sem --remote)
EOF
      exit 0
      ;;
    *)
      echo "[refresh] Opção desconhecida: $1 (usa -h)" >&2
      exit 1
      ;;
  esac
done

if [[ "$WIPE_VOLUMES" -eq 1 ]]; then
  echo "[refresh] AVISO: --wipe-volumes remove volumes (base de dados dentro do Docker será apagada)." >&2
fi

if [[ "$SKIP_GIT" -eq 0 ]]; then
  if git -C "$ROOT" rev-parse --git-dir &>/dev/null; then
    echo "[refresh] git pull (repo pai)..."
    git -C "$ROOT" pull --recurse-submodules=no
    echo "[refresh] submódulos (sync + init)..."
    git -C "$ROOT" submodule sync --recursive 2>/dev/null || true
    git -C "$ROOT" submodule update --init --recursive
    if [[ "$PINNED_SUBMODULES" -eq 0 ]]; then
      echo "[refresh] submódulos (pull do remoto: branch em .gitmodules)..."
      git -C "$ROOT" submodule update --remote --recursive
    fi
  else
    echo "[refresh] Aviso: $ROOT não é clone git; a saltar pull." >&2
  fi
fi

echo "[refresh] docker compose pull..."
compose pull

echo "[refresh] docker compose down..."
if [[ "$WIPE_VOLUMES" -eq 1 ]]; then
  compose down -v --remove-orphans
else
  compose down --remove-orphans
fi

UP_ARGS=()
[[ "$PUBLIC_IP" -eq 1 ]] && UP_ARGS=(--public-ip)

echo "[refresh] ./infra/up.sh ${UP_ARGS[*]:-}"
exec "$INFRA_DIR/up.sh" "${UP_ARGS[@]}"
