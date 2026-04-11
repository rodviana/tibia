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

ensure_env_variant() {
  local relative_path="$1"
  local example_relative_path="$2"
  local target="$INFRA_DIR/$relative_path"
  local example="$INFRA_DIR/$example_relative_path"
  local label="infra/$relative_path"
  if [[ ! -f "$target" ]]; then
    cp "$example" "$target"
    echo "[up] Criado $label a partir de $example_relative_path."
  fi
}

# Lê uma linha KEY=value de .env (sem expandir o resto do ficheiro).
read_ot_env_line() {
  local key="$1" file="$2"
  grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r' | sed 's/^"//;s/"$//'
}

# Garante canary/config.lua e alinha MySQL/IP/portas/datapack com o .env do Canary escolhido (modo --canary-local).
ensure_canary_local_config() {
  local env_file="$1"
  local cfg="$ROOT/canary/config.lua"
  if [[ ! -f "$cfg" ]]; then
    cp "$ROOT/canary/config.lua.dist" "$cfg"
    echo "[up] Criado canary/config.lua a partir de config.lua.dist."
  fi
  if [[ ! -f "$env_file" ]]; then
    echo "[up] Aviso: $env_file em falta; não sincronizei canary/config.lua com OT_*." >&2
    return 0
  fi
  local h u p db port ip login game status dpack
  h="$(read_ot_env_line OT_DB_HOST "$env_file")"
  u="$(read_ot_env_line OT_DB_USER "$env_file")"
  p="$(read_ot_env_line OT_DB_PASSWORD "$env_file")"
  db="$(read_ot_env_line OT_DB_DATABASE "$env_file")"
  port="$(read_ot_env_line OT_DB_PORT "$env_file")"
  ip="$(read_ot_env_line OT_SERVER_IP "$env_file")"
  login="$(read_ot_env_line OT_SERVER_LOGIN_PORT "$env_file")"
  game="$(read_ot_env_line OT_SERVER_GAME_PORT "$env_file")"
  status="$(read_ot_env_line OT_SERVER_STATUS_PORT "$env_file")"
  dpack="$(read_ot_env_line OT_SERVER_DATA "$env_file")"
  export OT_CFG_SYNC_HOST="$h" OT_CFG_SYNC_USER="$u" OT_CFG_SYNC_PASS="$p" OT_CFG_SYNC_DB="$db" \
    OT_CFG_SYNC_PORT="$port" OT_CFG_SYNC_IP="$ip" OT_CFG_SYNC_LOGIN="$login" OT_CFG_SYNC_GAME="$game" \
    OT_CFG_SYNC_STATUS="$status" OT_CFG_SYNC_DPACK="$dpack"
  perl -i -pe '
    s/^mysqlHost = .*/mysqlHost = "$ENV{OT_CFG_SYNC_HOST}"/ if length $ENV{OT_CFG_SYNC_HOST};
    s/^mysqlUser = .*/mysqlUser = "$ENV{OT_CFG_SYNC_USER}"/ if length $ENV{OT_CFG_SYNC_USER};
    s/^mysqlPass = .*/mysqlPass = "$ENV{OT_CFG_SYNC_PASS}"/ if length $ENV{OT_CFG_SYNC_PASS};
    s/^mysqlDatabase = .*/mysqlDatabase = "$ENV{OT_CFG_SYNC_DB}"/ if length $ENV{OT_CFG_SYNC_DB};
    s/^mysqlPort = .*/mysqlPort = $ENV{OT_CFG_SYNC_PORT}/ if length $ENV{OT_CFG_SYNC_PORT};
    s/^ip = .*/ip = "$ENV{OT_CFG_SYNC_IP}"/ if length $ENV{OT_CFG_SYNC_IP};
    s/^loginProtocolPort = .*/loginProtocolPort = $ENV{OT_CFG_SYNC_LOGIN}/ if length $ENV{OT_CFG_SYNC_LOGIN};
    s/^gameProtocolPort = .*/gameProtocolPort = $ENV{OT_CFG_SYNC_GAME}/ if length $ENV{OT_CFG_SYNC_GAME};
    s/^statusProtocolPort = .*/statusProtocolPort = $ENV{OT_CFG_SYNC_STATUS}/ if length $ENV{OT_CFG_SYNC_STATUS};
    s/^dataPackDirectory = .*/dataPackDirectory = "$ENV{OT_CFG_SYNC_DPACK}"/ if length $ENV{OT_CFG_SYNC_DPACK};
  ' "$cfg"
  echo "[up] canary/config.lua alinhado com $env_file (mysql, ip, portas, dataPack)."
}

bootstrap_public_ip() {
  local canary_env_file="${1:-$INFRA_DIR/canary/.env}"
  local web_env_file="${2:-$INFRA_DIR/otserver-web/.env}"
  local token pub
  token="$(curl -fsS -m 2 -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || true)"
  pub=""
  if [[ -n "$token" ]]; then
    pub="$(curl -fsS -m 2 -H "X-aws-ec2-metadata-token: $token" \
      "http://169.254.169.254/latest/meta-data/public-ipv4" 2>/dev/null || true)"
  fi
  if [[ -n "$pub" ]]; then
    perl -i -pe "s/^OT_SERVER_IP=.*/OT_SERVER_IP=$pub/" "$canary_env_file"
    perl -i -pe "s/^OT_GAMESERVER_IP=.*/OT_GAMESERVER_IP=$pub/" "$web_env_file"
    echo "[up] OT_SERVER_IP e OT_GAMESERVER_IP = $pub (metadata EC2)."
  else
    echo "[up] Aviso: sem IPv4 público na metadata. Define IP/domínio nos .env."
  fi
}

BOOTSTRAP_IP=0
CANARY_LOCAL=0
DOCKER_ARGS=()
ENV_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --public-ip) BOOTSTRAP_IP=1; shift ;;
    --canary-local) CANARY_LOCAL=1; shift ;;
    --env)
      if [[ $# -lt 2 ]]; then
        echo "[up] Erro: --env requer um nome (ex.: local)." >&2
        exit 1
      fi
      ENV_NAME="$2"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
  ./infra/up.sh                 # submódulos + .env + up -d --build
  ./infra/up.sh --env local     # usa infra/*/.env.local + infra/environments/local.compose.env
  ./infra/up.sh --canary-local  # build do Canary em ../canary + monta canary/config.lua (precisa de infra/canary/secrets/github_token.txt)
  ./infra/up.sh --env local --canary-local
  ./infra/up.sh --public-ip     # idem + OT_SERVER_IP / OT_GAMESERVER_IP = IPv4 EC2
  ./infra/up.sh ps
Atualizar tudo na EC2 (pull + down + up): ./infra/stack-refresh.sh
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

COMPOSE_FLAGS=()
SELECTED_CANARY_ENV="$INFRA_DIR/canary/.env"
SELECTED_WEBSERVER_ENV="$INFRA_DIR/otserver-web/.env"

if [[ -n "$ENV_NAME" ]]; then
  case "$ENV_NAME" in
    local)
      ensure_env_variant "mysql/.env.local" "mysql/.env.local.example"
      ensure_env_variant "canary/.env.local" "canary/.env.local.example"
      ensure_env_variant "otserver-web/.env.local" "otserver-web/.env.local.example"
      ensure_env_variant "environments/local.compose.env" "environments/local.compose.env.example"
      COMPOSE_FLAGS=(--env-file "infra/environments/local.compose.env")
      SELECTED_CANARY_ENV="$INFRA_DIR/canary/.env.local"
      SELECTED_WEBSERVER_ENV="$INFRA_DIR/otserver-web/.env.local"
      ;;
    *)
      echo "[up] Erro: ambiente '$ENV_NAME' não suportado. Usa sem --env ou --env local." >&2
      exit 1
      ;;
  esac
fi

if [[ "$BOOTSTRAP_IP" -eq 1 ]]; then
  bootstrap_public_ip "$SELECTED_CANARY_ENV" "$SELECTED_WEBSERVER_ENV"
fi

COMPOSE_FILES=(-f infra/docker-compose.yml)
if [[ "$CANARY_LOCAL" -eq 1 ]]; then
  COMPOSE_FILES+=(-f infra/docker-compose.canary-local.yml)
  ensure_canary_local_config "$SELECTED_CANARY_ENV"
  _token="${GITHUB_TOKEN_FILE:-$INFRA_DIR/canary/secrets/github_token.txt}"
  if [[ ! -f "$_token" ]]; then
    echo "[up] ERRO: --canary-local precisa de token GitHub para o build vcpkg." >&2
    echo "[up] Cria o ficheiro: echo SEU_TOKEN > infra/canary/secrets/github_token.txt" >&2
    echo "[up] ou define GITHUB_TOKEN_FILE com caminho absoluto." >&2
    exit 1
  fi
fi

if [[ ${#DOCKER_ARGS[@]} -eq 0 ]]; then
  DOCKER_ARGS=(up -d --build)
fi

echo "[up] docker compose ${COMPOSE_FLAGS[*]} ${COMPOSE_FILES[*]} ${DOCKER_ARGS[*]}"
if docker compose version &>/dev/null; then
  docker compose "${COMPOSE_FLAGS[@]}" "${COMPOSE_FILES[@]}" "${DOCKER_ARGS[@]}"
elif sudo docker compose version &>/dev/null; then
  sudo docker compose "${COMPOSE_FLAGS[@]}" "${COMPOSE_FILES[@]}" "${DOCKER_ARGS[@]}"
else
  echo "[up] Erro: Docker Compose v2 em falta (newgrp docker ou sudo)." >&2
  exit 1
fi
