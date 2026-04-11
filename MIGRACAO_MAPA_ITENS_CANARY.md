# Migracao de mapa e itens no Canary

Este documento explica os principais arquivos envolvidos na importacao de mapa e itens entre projetos `Canary`.

## 1. Arquivos do mapa

### `data-otservbr-global/world/<mapa>.otbm`

Este e o arquivo principal do mapa.

Exemplo:
- `otservbr.otbm`

Ele contem:
- terreno
- tiles
- houses posicionadas no mapa
- itens colocados no mapa
- towns
- estrutura geral do mundo

No `Canary`, o nome do mapa principal e definido em `config.lua` pela chave `mapName`.

### `data-otservbr-global/world/<mapa>-monster.xml`

Define os spawns de monstros do mapa principal.

Exemplo:
- `otservbr-monster.xml`

Sem esse arquivo:
- o mapa pode carregar
- mas os monstros nao vao nascer

### `data-otservbr-global/world/<mapa>-npc.xml`

Define os spawns de NPCs do mapa principal.

Exemplo:
- `otservbr-npc.xml`

Sem esse arquivo:
- o mapa abre normalmente
- mas os NPCs nao aparecem

### `data-otservbr-global/world/<mapa>-house.xml`

Define as houses do mapa.

Exemplo:
- `otservbr-house.xml`

Esse arquivo contem:
- IDs das houses
- nome das houses
- tamanho
- tiles pertencentes a cada house

Sem ele:
- as houses podem deixar de funcionar corretamente
- compras, aluguel e ownership podem quebrar

### `data-otservbr-global/world/<mapa>-zones.xml`

Define zonas especiais do mapa.

Exemplo:
- `otservbr-zones.xml`

Pode ser usado para:
- areas de protecao
- zonas customizadas
- regioes usadas por sistemas especificos

Nem todo projeto usa esse arquivo intensamente, mas no Canary ele faz parte do pacote do mapa.

## 2. Arquivo de configuracao do mapa

### `config.lua`

Esse arquivo controla qual mapa o servidor vai carregar.

Campos importantes:
- `dataPackDirectory`
- `mapName`
- `toggleMapCustom`

Exemplo:
- `dataPackDirectory = "data-otservbr-global"`
- `mapName = "otservbr"`

Isso faz o servidor procurar:
- `data-otservbr-global/world/otservbr.otbm`
- `data-otservbr-global/world/otservbr-monster.xml`
- `data-otservbr-global/world/otservbr-npc.xml`
- `data-otservbr-global/world/otservbr-house.xml`
- `data-otservbr-global/world/otservbr-zones.xml`

## 3. Mapas customizados

### `data-otservbr-global/world/custom/`

Essa pasta e usada para mapas adicionais.

Se `toggleMapCustom = true`, o Canary tenta carregar automaticamente os arquivos `.otbm` dessa pasta.

Uso comum:
- ilhas extras
- areas de evento
- partes adicionais do mundo
- mapas temporarios

Observacao:
cada mapa custom tambem pode precisar de seus arquivos auxiliares, dependendo da implementacao.

## 4. Arquivos dos itens

### `data/items/items.xml`

Esse e um dos arquivos mais importantes do sistema de itens.

Ele define:
- nome do item
- peso
- atributos
- ataque
- defesa
- slot
- tipo de arma
- scripts vinculados
- imbuements
- comportamento extra

Se voce importar itens de outro projeto, normalmente precisa copiar ou mesclar esse arquivo.

### `data/items/appearances.dat`

Esse arquivo contem os dados de aparencia dos objetos.

Ele esta ligado ao visual e ao reconhecimento dos itens pelo sistema.

No seu fork do Canary, o carregamento dos itens depende primeiro das aparencias e depois do `items.xml`.

Se o item nao existir corretamente nas aparencias:
- pode nao aparecer
- pode gerar erro
- pode nao ser criado corretamente no mapa

## 5. Scripts ligados aos itens

Além do `items.xml`, muitos itens dependem de scripts.

Pastas comuns:

### `data/scripts/actions/`

Usada para itens que executam alguma acao ao usar.

Exemplo:
- alavancas
- baus
- portais
- itens de quest

### `data/scripts/movements/`

Usada para comportamento ao pisar, equipar, mover ou interagir com tiles/itens.

Exemplo:
- teleportes
- pisos especiais
- traps
- equipamentos com efeito ao equipar

### `data/scripts/weapons/`

Usada para armas com logica customizada.

Exemplo:
- armas com dano especial
- armas com efeito em area
- armas com script proprio

### `data/scripts/spells/`

As vezes um item depende de spells customizadas para funcionar corretamente.

## 6. Tabelas auxiliares do mapa

### `data-otservbr-global/startup/tables/*.lua`

Esses arquivos carregam acoes e atributos extras no mapa sem precisar editar o `.otbm`.

Exemplos:
- `item.lua`
- `create_item.lua`
- `item_unmovable.lua`
- `teleport.lua`
- `teleport_item.lua`
- `door_key.lua`
- `door_level.lua`
- `door_quest.lua`

Essas tabelas podem definir:
- action ids
- unique ids
- teleportes
- portas especiais
- itens criados automaticamente no mapa
- itens imoveis
- textos e atributos extras

Se voce importar um mapa de outro projeto e esquecer essas tabelas:
- quests podem quebrar
- portas podem nao funcionar
- teleportes podem falhar
- itens especiais podem nao existir

## 7. O que copiar ao migrar mapa de outro Canary

Para migrar um mapa corretamente, o ideal e copiar em conjunto:

### Pacote minimo do mapa

- `<mapa>.otbm`
- `<mapa>-monster.xml`
- `<mapa>-npc.xml`
- `<mapa>-house.xml`
- `<mapa>-zones.xml`

### Pacote de itens

- `data/items/items.xml`
- `data/items/appearances.dat`
- scripts relacionados em `data/scripts/...`

### Pacote auxiliar

- tabelas em `data-otservbr-global/startup/tables/...`
- NPCs customizados
- monstros customizados
- spells e actions usadas no mapa

## 8. Principais riscos

### Incompatibilidade de itens

Se o mapa usa IDs de itens que nao existem no seu `items.xml` ou `appearances.dat`, o servidor pode falhar ou ignorar itens.

### Falta de XML auxiliar

Se copiar so o `.otbm`, voce pode ficar sem:
- monstros
- NPCs
- houses
- zones

### Scripts ausentes

Mesmo com o mapa certo, varias mecanicas podem nao funcionar sem os scripts.

### Versoes diferentes do Canary

Se os dois projetos estiverem em revisoes muito diferentes, pode haver incompatibilidade entre:
- mapa
- itens
- scripts
- assets do cliente

## 9. Resumo

No Canary, mapa e itens funcionam como um conjunto.

Para importar corretamente de outro projeto, normalmente voce precisa alinhar:
- mapa `.otbm`
- XMLs auxiliares do mapa
- `items.xml`
- `appearances.dat`
- scripts
- tabelas auxiliares
- assets/cliente compativeis

Copiar apenas um arquivo quase nunca e suficiente em projetos customizados.
