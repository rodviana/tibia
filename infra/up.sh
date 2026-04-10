#!/usr/bin/env bash
# Arranque da stack: submódulos Git (canary, otserver-web), .env e docker compose.
#
# Clone na EC2 (recomendado):
#   git clone --recurse-submodules https://github.com/rodviana/tibia.git
#
# Se já clonaste sem submódulos:
#   git pull && git submodule update --init --recursive
#
set -euo pipefail

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$INFRA_DIR/.." && pwd)"
cd "$ROOT"

sync_submodules() {
  if [[ -f "$ROOT/otserver-web/ot-login-api/pom.xml" && -f "$ROOT/canary/schema.sql" ]]; then
    return 0
  fi
  echo "[up] Falta código em canary/ ou otserver-web/ (submódulos). A sincronizar..."
  if ! git -C "$ROOT" rev-parse --git-dir &>/dev/null; then
    echo "[up] ERRO: $ROOT não é um clone git. Usa git clone --recurse-submodules ..." >&2
    exit 1
  fi
  git -C "$ROOT" submodule sync --recursive 2>/dev/null || true
  git -C "$ROOT" submodule update --init --recursive || {
    echo "[up] Falhou. Garante .gitmodules no repo, faz git pull e tenta de novo." >&2
    exit 1
  }
}

ensure_env() {
  local name="$1"
  local dir="$INFRA_DIR/$name"
  if [[ ! -f "$dir/.env" ]]; then
    cp "$dir/.env.example" "$dir/.env"
    echo "[up] Criado infra/$name/.env (revisa passwords em produção)."
  fi
}

# O mount ../canary/data:/canary/data substitui o /canary/data da imagem. O repositório Canary
# ignora data/items/items.xml no .gitignore, pelo que clones Git ficam sem esse ficheiro.
ensure_canary_core_items_from_image() {
  local items_xml="$ROOT/canary/data/items/items.xml"
  [[ -f "$items_xml" ]] && return 0

  local docker_cli
  if docker info &>/dev/null; then
    docker_cli=docker
  elif sudo docker info &>/dev/null; then
    docker_cli="sudo docker"
  else
    echo "[up] Aviso: Docker indisponível; não foi possível copiar items da imagem Canary." >&2
    return 0
  fi

  local image
  image="$(grep -E '^[[:space:]]*CANARY_IMAGE=' "$INFRA_DIR/canary/.env" 2>/dev/null | tail -1 | sed "s/^[^=]*=//;s/^[[:space:]]*//;s/[[:space:]]*$//;s/^[\"']//;s/[\"']$//")"
  [[ -z "$image" ]] && image="ghcr.io/opentibiabr/canary:latest"

  echo "[up] Falta canary/data/items/items.xml; a copiar data/items/ da imagem ${image}..."
  mkdir -p "$ROOT/canary/data/items"
  local cid
  cid="$($docker_cli create "$image" 2>/dev/null)" || {
    echo "[up] ERRO: docker create falhou (ex.: imagem em falta — faz pull do serviço server)." >&2
    exit 1
  }
  if ! $docker_cli cp "$cid:/canary/data/items/." "$ROOT/canary/data/items/"; then
    $docker_cli rm "$cid" &>/dev/null || true
    echo "[up] ERRO: docker cp de /canary/data/items falhou." >&2
    exit 1
  fi
  $docker_cli rm "$cid" &>/dev/null || true
  echo "[up] canary/data/items/ preenchido a partir da imagem."
}

bootstrap_public_ip() {
  local token pub
  token="$(curl -fsS -m 2 -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || true)"
  pub=""
  if [[ -n "$token" ]]; then
    pub="$(curl -fsS -m 2 -H "X-aws-ec2-metadata-token: $token" \
      "http://169.254.169.254/latest/meta-data/public-ipv4" 2>/dev/null || true)"
  fi
  if [[ -n "$pub" ]]; then
    perl -i -pe "s/^OT_SERVER_IP=.*/OT_SERVER_IP=$pub/" "$INFRA_DIR/canary/.env"
    perl -i -pe "s/^OT_GAMESERVER_IP=.*/OT_GAMESERVER_IP=$pub/" "$INFRA_DIR/otserver-web/.env"
    echo "[up] OT_SERVER_IP e OT_GAMESERVER_IP = $pub (metadata EC2)."
  else
    echo "[up] Aviso: sem IPv4 público na metadata. Define IP/domínio nos .env."
  fi
}

BOOTSTRAP_IP=0
DOCKER_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --public-ip) BOOTSTRAP_IP=1; shift ;;
    -h|--help)
      cat <<'EOF'
  ./infra/up.sh                 # submódulos + .env + up -d --build
  ./infra/up.sh --public-ip     # idem + OT_SERVER_IP / OT_GAMESERVER_IP = IPv4 EC2
  ./infra/up.sh ps
Clone: git clone --recurse-submodules https://github.com/rodviana/tibia.git
EOF
      exit 0
      ;;
    *) DOCKER_ARGS+=("$1"); shift ;;
  esac
done

if [[ -n "${OT_BOOTSTRAP_PUBLIC_IP:-}" && "$OT_BOOTSTRAP_PUBLIC_IP" != "0" ]]; then
  BOOTSTRAP_IP=1
fi

sync_submodules
ensure_env mysql
ensure_env canary
ensure_env otserver-web
ensure_canary_core_items_from_image

if [[ "$BOOTSTRAP_IP" -eq 1 ]]; then
  bootstrap_public_ip
fi

if [[ ${#DOCKER_ARGS[@]} -eq 0 ]]; then
  DOCKER_ARGS=(up -d --build)
fi

echo "[up] docker compose -f infra/docker-compose.yml ${DOCKER_ARGS[*]}"
if docker compose version &>/dev/null; then
  docker compose -f infra/docker-compose.yml "${DOCKER_ARGS[@]}"
elif sudo docker compose version &>/dev/null; then
  sudo docker compose -f infra/docker-compose.yml "${DOCKER_ARGS[@]}"
else
  echo "[up] Erro: Docker Compose v2 em falta (newgrp docker ou sudo)." >&2
  exit 1
fi
