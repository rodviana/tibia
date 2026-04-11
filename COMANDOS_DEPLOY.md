# Comandos de Deploy

## 1. Fazer push do projeto `tibia` e dos submodulos

### Ver status geral

```bash
cd /c/git/tibia
git status
git submodule status
```

### Push manual, um por um

```bash
cd /c/git/tibia/canary
git add .
git commit -m "Sua mensagem"
git push origin main
```

```bash
cd /c/git/tibia/otserver-web
git add .
git commit -m "Sua mensagem"
git push origin master
```

```bash
cd /c/git/tibia
git add canary otserver-web
git commit -m "Atualiza ponteiros dos submodulos"
git push origin master
```

### Push rapido de tudo

```bash
cd /c/git/tibia
git -C canary push origin rodrigo
git -C otserver-web push origin master
git push origin master
```

Se voce alterou arquivos dentro dos submodulos, faca `commit` neles antes do `git push` da raiz.

## 2. Fazer pull na EC2 e atualizar os arquivos no Docker

### Atualizar codigo na EC2

```bash
cd ~/tibia
git pull origin master
git submodule sync --recursive
git submodule update --init --recursive
```

### Ambientes disponiveis

#### Ambiente padrao

Usa os arquivos:

- `infra/mysql/.env`
- `infra/canary/.env`
- `infra/otserver-web/.env`

Esse e o fluxo normal para EC2/producao.

A taxa de XP (`rateExp`) e o resto da config do servidor ficam em **`canary/config.lua`** no servidor (o Compose monta esse ficheiro no contentor). O `./infra/up.sh` cria-o a partir de `canary/config.lua.dist` se ainda nao existir e alinha mysql/ip/portas com o `.env` do Canary. Se usares `docker compose` direto, garante que `canary/config.lua` existe antes.

#### Ambiente local

Usa os arquivos:

- `infra/mysql/.env.local`
- `infra/canary/.env.local`
- `infra/otserver-web/.env.local`
- `infra/environments/local.compose.env`

O script `infra/up.sh --env local` cria esses arquivos automaticamente a partir dos `.example` se eles ainda nao existirem.

### Subir tudo de uma vez

#### Ambiente padrao com o script do projeto

```bash
cd ~/tibia
sudo ./infra/up.sh
```

#### Ambiente local com o script do projeto

```bash
cd ~/tibia
sudo ./infra/up.sh --env local
```

#### Canary a partir do submodulo (build local + `canary/config.lua` do host)

Token GitHub opcional (acelera o vcpkg via NuGet): `echo SEU_TOKEN > infra/canary/secrets/github_token.txt`. Sem token, o primeiro build demora mais (compilacao a partir do codigo).

```bash
cd ~/tibia
sudo ./infra/up.sh --canary-local
# ou ambiente local:
sudo ./infra/up.sh --env local --canary-local
```

O `./infra/up.sh` sem esta flag ja usa `canary/config.lua` no host para rates; `--canary-local` adiciona **build** da imagem a partir do submodulo `canary/`.

#### Ambiente padrao com Docker Compose

```bash
cd ~/tibia
sudo docker compose -f infra/docker-compose.yml up -d --build
```

#### Ambiente local com Docker Compose

```bash
cd ~/tibia
cp infra/environments/local.compose.env.example infra/environments/local.compose.env
cp infra/mysql/.env.local.example infra/mysql/.env.local
cp infra/canary/.env.local.example infra/canary/.env.local
cp infra/otserver-web/.env.local.example infra/otserver-web/.env.local
sudo docker compose --env-file infra/environments/local.compose.env -f infra/docker-compose.yml up -d --build
```

### Atualizar um servico por vez

#### `server` (Canary)

```bash
cd ~/tibia
git pull origin master
git submodule update --init --recursive
sudo docker compose -f infra/docker-compose.yml pull server
sudo docker compose -f infra/docker-compose.yml up -d server
```

#### `api`

```bash
cd ~/tibia
git pull origin master
git submodule update --init --recursive
sudo docker compose -f infra/docker-compose.yml build api
sudo docker compose -f infra/docker-compose.yml up -d api
```

#### `site`

```bash
cd ~/tibia
git pull origin master
git submodule update --init --recursive
sudo docker compose -f infra/docker-compose.yml build site
sudo docker compose -f infra/docker-compose.yml up -d site
```

#### `database`

```bash
cd ~/tibia
sudo docker compose -f infra/docker-compose.yml pull database
sudo docker compose -f infra/docker-compose.yml up -d database
```

### Atualizar um servico por vez no ambiente local

#### `server` (Canary)

```bash
cd ~/tibia
sudo ./infra/up.sh --env local up -d server
```

#### `api`

```bash
cd ~/tibia
sudo ./infra/up.sh --env local up -d api
```

#### `site`

```bash
cd ~/tibia
sudo ./infra/up.sh --env local up -d site
```

#### `database`

```bash
cd ~/tibia
sudo ./infra/up.sh --env local up -d database
```

## 3. Como subir um container de uma nova imagem

### Quando a imagem vem de registry

Exemplo para trocar a imagem do `server`:

1. Edite `infra/canary/.env` e ajuste:

```env
CANARY_IMAGE=ghcr.io/opentibiabr/canary:latest
```

2. Depois rode:

```bash
cd ~/tibia
sudo docker compose -f infra/docker-compose.yml pull server
sudo docker compose -f infra/docker-compose.yml up -d server
```

### Quando a imagem precisa ser rebuildada localmente

Exemplo para `api` e `site`:

```bash
cd ~/tibia
sudo docker compose -f infra/docker-compose.yml build api site
sudo docker compose -f infra/docker-compose.yml up -d api site
```

## 4. Comandos uteis de verificacao

### Ambiente padrao

```bash
cd ~/tibia
sudo docker compose -f infra/docker-compose.yml ps
sudo docker compose -f infra/docker-compose.yml logs -f api
sudo docker compose -f infra/docker-compose.yml logs -f site
sudo docker compose -f infra/docker-compose.yml logs -f server
```

### Ambiente local

```bash
cd ~/tibia
sudo docker compose --env-file infra/environments/local.compose.env -f infra/docker-compose.yml ps
sudo docker compose --env-file infra/environments/local.compose.env -f infra/docker-compose.yml logs -f api
sudo docker compose --env-file infra/environments/local.compose.env -f infra/docker-compose.yml logs -f site
sudo docker compose --env-file infra/environments/local.compose.env -f infra/docker-compose.yml logs -f server
```
