#!/usr/bin/env bash
# Arranque da stack: submódulos Git (canary, otserver-web), .env e docker compose.
#
# Alvo comum: Amazon Linux 2023 na EC2 — Docker + plugin compose + python3 (dnf install -y docker python3;
#   sudo systemctl enable --now docker; sudo usermod -aG docker ec2-user).
#
# Clone na EC2 (recomendado):
#   git clone --recurse-submodules https://github.com/rodviana/tibia.git
#
# Se já clonaste sem submódulos:
#   git pull && git submodule update --init --recursive
#
# items.xml: em alguns clones fica fora do Git (.gitignore em canary/). O compose monta
# ../canary/data por cima da imagem; sem items.xml o Canary morre ao arrancar.
# Por defeito tenta raw no fork rodviana/canary (branch rodrigo); se 404, usa upstream main.
#   CANARY_ITEMS_XML_URL=...  — se definido, usa só este URL (sem fallback).
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

# Garante canary/config.lua (ou config.lua.fun-server) no host e alinha MySQL/IP/portas/datapack com o .env do Canary.
ensure_canary_host_config() {
  local env_file="$1"
  local cfg="${2:-$ROOT/canary/config.lua}"
  if [[ ! -f "$cfg" ]]; then
    cp "$ROOT/canary/config.lua.dist" "$cfg"
    echo "[up] Criado $cfg a partir de config.lua.dist."
  fi
  if [[ ! -f "$env_file" ]]; then
    echo "[up] Aviso: $env_file em falta; não sincronizei $(basename "$cfg") com OT_*." >&2
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
  if ! command -v python3 &>/dev/null; then
    echo "[up] ERRO: python3 em falta (Amazon Linux: sudo dnf install -y python3)." >&2
    exit 1
  fi
  OT_CFG_SYNC_CFG_PATH="$cfg" python3 <<'PY'
import os, re
path = os.environ["OT_CFG_SYNC_CFG_PATH"]
with open(path, "r", encoding="utf-8", errors="replace") as f:
    s = f.read()

def sub(pat: str, repl: str) -> None:
    global s
    s = re.sub(pat, repl, s, flags=re.MULTILINE)

h, u, pw, db = map(os.environ.get, ("OT_CFG_SYNC_HOST", "OT_CFG_SYNC_USER", "OT_CFG_SYNC_PASS", "OT_CFG_SYNC_DB"))
port, ip = os.environ.get("OT_CFG_SYNC_PORT"), os.environ.get("OT_CFG_SYNC_IP")
login, game, status = os.environ.get("OT_CFG_SYNC_LOGIN"), os.environ.get("OT_CFG_SYNC_GAME"), os.environ.get("OT_CFG_SYNC_STATUS")
dpack = os.environ.get("OT_CFG_SYNC_DPACK")
if h:
    sub(r"^mysqlHost = .*", f'mysqlHost = "{h}"')
if u:
    sub(r"^mysqlUser = .*", f'mysqlUser = "{u}"')
if pw:
    sub(r"^mysqlPass = .*", f'mysqlPass = "{pw}"')
if db:
    sub(r"^mysqlDatabase = .*", f'mysqlDatabase = "{db}"')
if port:
    sub(r"^mysqlPort = .*", f"mysqlPort = {port}")
if ip:
    sub(r"^ip = .*", f'ip = "{ip}"')
if login:
    sub(r"^loginProtocolPort = .*", f"loginProtocolPort = {login}")
if game:
    sub(r"^gameProtocolPort = .*", f"gameProtocolPort = {game}")
if status:
    sub(r"^statusProtocolPort = .*", f"statusProtocolPort = {status}")
if dpack:
    sub(r"^dataPackDirectory = .*", f'dataPackDirectory = "{dpack}"')
with open(path, "w", encoding="utf-8") as f:
    f.write(s)
PY
  echo "[up] $(basename "$cfg") alinhado com $env_file (mysql, ip, portas, dataPack)."
}

# O bind mount ../canary/data:/canary/data substitui o data/ da imagem Docker. Sem items.xml
# (muitas vezes omitido do clone por .gitignore) o servidor falha com "Cannot load: items.xml".
ensure_canary_items_xml() {
  local target="$ROOT/canary/data/items/items.xml"
  if [[ -f "$target" ]]; then
    return 0
  fi
  mkdir -p "$ROOT/canary/data/items"
  if ! command -v curl &>/dev/null; then
    echo "[up] ERRO: falta $target e o curl não está instalado. Copia items.xml para esse caminho ou instala curl." >&2
    exit 1
  fi
  local fork_url="https://raw.githubusercontent.com/rodviana/canary/rodrigo/data/items/items.xml"
  local upstream_url="https://raw.githubusercontent.com/opentibiabr/canary/main/data/items/items.xml"
  echo "[up] Falta canary/data/items/items.xml (normal em clone sem ficheiros ignorados pelo Git). A descarregar..."
  if [[ -n "${CANARY_ITEMS_XML_URL:-}" ]]; then
    if ! curl -fL --connect-timeout 30 --retry 3 --retry-delay 2 -o "$target.part" "$CANARY_ITEMS_XML_URL"; then
      rm -f "$target.part"
      echo "[up] ERRO: download de items.xml falhou (CANARY_ITEMS_XML_URL)." >&2
      exit 1
    fi
    mv "$target.part" "$target"
    echo "[up] Instalado: $target (origem: CANARY_ITEMS_XML_URL)"
    return 0
  fi
  if curl -fL --connect-timeout 30 --retry 2 --retry-delay 2 -o "$target.part" "$fork_url"; then
    mv "$target.part" "$target"
    echo "[up] Instalado: $target (fork rodviana/canary rodrigo)"
    return 0
  fi
  rm -f "$target.part"
  echo "[up] items.xml não está no fork no GitHub; a tentar upstream opentibiabr/canary main..."
  if ! curl -fL --connect-timeout 30 --retry 3 --retry-delay 2 -o "$target.part" "$upstream_url"; then
    rm -f "$target.part"
    echo "[up] ERRO: não foi possível obter items.xml (fork nem upstream). Publica data/items/items.xml no fork ou define CANARY_ITEMS_XML_URL." >&2
    exit 1
  fi
  mv "$target.part" "$target"
  echo "[up] Instalado: $target (upstream main)"
}

# Login na 7171 pode funcionar com SG só nessa porta; ao escolher personagem o cliente liga à porta de jogo (API/Canary).
validate_client_game_env() {
  local canary_env="$1"
  local web_env="$2"
  [[ -f "$canary_env" && -f "$web_env" ]] || return 0
  local sip gip sport gport lport
  sip="$(read_ot_env_line OT_SERVER_IP "$canary_env")"
  gip="$(read_ot_env_line OT_GAMESERVER_IP "$web_env")"
  sport_raw="$(read_ot_env_line OT_SERVER_GAME_PORT "$canary_env")"
  gport_raw="$(read_ot_env_line OT_GAMESERVER_PORT "$web_env")"
  lport="$(read_ot_env_line OT_SERVER_LOGIN_PORT "$canary_env")"
  [[ -z "$lport" ]] && lport=7171
  if [[ -n "$sport_raw" && -n "$gport_raw" && "$sport_raw" != "$gport_raw" ]]; then
    echo "[up] ERRO: OT_SERVER_GAME_PORT ($sport_raw) ≠ OT_GAMESERVER_PORT ($gport_raw)." >&2
    echo "[up] Ao seleccionar personagem o cliente usa o IP/porta do login API (otserver-web); alinha os dois .env." >&2
    exit 1
  fi
  sport="${sport_raw:-7172}"
  gport="${gport_raw:-7172}"
  if [[ -n "$sip" && -n "$gip" && "$sip" != "$gip" ]]; then
    echo "[up] Aviso: OT_SERVER_IP ($sip) ≠ OT_GAMESERVER_IP ($gip); o mundo anunciado ao cliente pode não bater com o Canary." >&2
  fi
  if [[ "$sip" == "127.0.0.1" || "$gip" == "127.0.0.1" ]]; then
    echo "[up] Aviso: IP 127.0.0.1 no .env não serve para jogadores remotos (login HTTP / entrada no mundo)." >&2
  fi
  echo "[up] EC2/security group: TCP $lport (login) e $sport (jogo — necessário após escolher personagem)."
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
    if ! command -v python3 &>/dev/null; then
      echo "[up] ERRO: python3 em falta para --public-ip (sudo dnf install -y python3)." >&2
      exit 1
    fi
    OT_BOOTSTRAP_PUB="$pub" OT_BOOTSTRAP_CANARY_ENV="$canary_env_file" OT_BOOTSTRAP_WEB_ENV="$web_env_file" python3 <<'PY'
import os, re
pub = os.environ["OT_BOOTSTRAP_PUB"]
for key, path in (("OT_SERVER_IP", os.environ["OT_BOOTSTRAP_CANARY_ENV"]), ("OT_GAMESERVER_IP", os.environ["OT_BOOTSTRAP_WEB_ENV"])):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        c = f.read()
    c = re.sub(rf"^{key}=.*", f"{key}={pub}", c, flags=re.MULTILINE)
    with open(path, "w", encoding="utf-8") as f:
        f.write(c)
PY
    echo "[up] OT_SERVER_IP e OT_GAMESERVER_IP = $pub (metadata EC2)."
  else
    echo "[up] Aviso: sem IPv4 público na metadata. Define IP/domínio nos .env."
  fi
}

BOOTSTRAP_IP=0
CANARY_LOCAL=0
CANARY_FUN=0
DOCKER_ARGS=()
ENV_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --public-ip) BOOTSTRAP_IP=1; shift ;;
    --canary-local) CANARY_LOCAL=1; shift ;;
    --canary-fun) CANARY_FUN=1; shift ;;
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
  ./infra/up.sh --canary-local  # build da imagem Canary a partir do submódulo (token NuGet opcional)
  ./infra/up.sh --canary-fun    # monta canary/config.lua.fun-server como /canary/config.lua
  ./infra/up.sh --env local --canary-local
  ./infra/up.sh --public-ip     # idem + OT_SERVER_IP / OT_GAMESERVER_IP = IPv4 EC2
  ./infra/up.sh ps
Atualizar tudo na EC2 (pull + down + up): ./infra/stack-refresh.sh [--canary-fun]
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
ensure_canary_items_xml
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

CANARY_CFG_HOST="$ROOT/canary/config.lua"
[[ "$CANARY_FUN" -eq 1 ]] && CANARY_CFG_HOST="$ROOT/canary/config.lua.fun-server"
ensure_canary_host_config "$SELECTED_CANARY_ENV" "$CANARY_CFG_HOST"
# Só valida antes de `up` — com `down`/`ps` não deve bloquear por .env inconsistente.
if [[ ${#DOCKER_ARGS[@]} -eq 0 || "${DOCKER_ARGS[0]:-}" == "up" ]]; then
  validate_client_game_env "$SELECTED_CANARY_ENV" "$SELECTED_WEBSERVER_ENV"
fi

COMPOSE_FILES=(-f infra/docker-compose.yml)
if [[ "$CANARY_LOCAL" -eq 1 ]]; then
  COMPOSE_FILES+=(-f infra/docker-compose.canary-local.yml)
  _token="${GITHUB_TOKEN_FILE:-$INFRA_DIR/canary/secrets/github_token.txt}"
  if [[ ! -f "$_token" ]]; then
    mkdir -p "$(dirname "$_token")"
    : >"$_token"
    echo "[up] Aviso: sem ficheiro de token GitHub; vcpkg compila dependências sem cache NuGet (mais lento)." >&2
    echo "[up] Opcional: echo SEU_TOKEN > infra/canary/secrets/github_token.txt para acelerar o build." >&2
  fi
fi
if [[ "$CANARY_FUN" -eq 1 ]]; then
  COMPOSE_FILES+=(-f infra/docker-compose.canary-fun.yml)
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
