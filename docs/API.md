# API do jogo: formato do JSON

Contrato entre o Elm, o Python e o Prolog para o **Grupo de Estudo na BCE**
(issue #9). As regras do jogo estão em [REGRAS.md](REGRAS.md).

Todas as rotas são `POST` e recebem e devolvem JSON. A documentação
interativa fica em http://localhost:8000/docs com o backend rodando.

## Como o código está dividido

```
Elm  ──JSON──▶  backend/app/main.py      valida o formato (Pydantic)
                backend/app/prolog.py    chama o Prolog pelo janus
                backend/prolog/bce_api.pl  converte strings em átomos
                backend/prolog/bce.pl      as regras (Mayara, #4)
```

O janus só troca inteiros, strings e listas com o Python. Por isso o
`bce_api.pl` traduz o JSON para os átomos e o termo `mesa/3` do `bce.pl`, e
o `bce.pl` não precisa saber que existe uma API.

## Tipos usados em várias rotas

Nomes de amigos e objetos são sempre em minúsculas e sem acento: `arthur`,
`bevi`, `felipe`, `gabriel`, `giovanna`, `joao`, `mayara`; `janela`,
`tomada`, `porta`, `estante`. Linhas e colunas começam em 0, com `(0, 0)`
no canto de cima à esquerda.

### Fase

O que não muda durante a partida.

```json
{
  "mesa": {
    "linhas": 2,
    "colunas": 3,
    "objetos": [
      {"objeto": "porta", "linha": 0, "coluna": 0},
      {"objeto": "tomada", "linha": 0, "coluna": 2}
    ]
  },
  "amigos": ["arthur", "joao", "mayara", "bevi"],
  "fixos": [{"amigo": "bevi", "linha": 1, "coluna": 1}],
  "manias": [
    {"amigo": "arthur", "tipo": "perto_de_objeto", "alvo": "porta"},
    {"amigo": "joao", "tipo": "na_cadeira_de", "alvo": "tomada"},
    {"amigo": "mayara", "tipo": "longe_de", "alvo": "joao"},
    {"amigo": "bevi", "tipo": "sem_vizinhos", "alvo": null}
  ]
}
```

- `fixos`: amigos que já começam sentados e não podem sair do lugar.
- `manias`: só para a tela mostrar nos cards. O Elm pode mandar a fase de
  volta com elas, mas o servidor ignora: quem decide as manias é o Prolog.

### Mania

`tipo` diz como ler `alvo`. É o que o decoder do Elm usa para montar o
`type Mania` do REGRAS.md.

| `tipo` | `alvo` | Exemplo | Elm |
|---|---|---|---|
| `perto_de_objeto` | objeto | `"porta"` | `PertoDeObjeto Porta` |
| `na_cadeira_de` | objeto | `"tomada"` | `NaCadeiraDe Tomada` |
| `sem_vizinhos` | `null` | `null` | `SemVizinhos` |
| `de_frente_para_algum` | lista de amigos | `["arthur", "joao"]` | `DeFrentePara [Arthur, Joao]` |
| `perto_de` | amigo | `"arthur"` | `PertoDe Arthur` |
| `lado_a_lado_com` | amigo | `"mayara"` | `LadoALadoCom Mayara` |
| `longe_de` | amigo | `"joao"` | `LongeDe Joao` |

### Lugar

`{"amigo": "bevi", "linha": 1, "coluna": 1}`: um amigo sentado numa cadeira.

### Estado (resposta)

O que muda a cada jogada. Toda rota que mexe no tabuleiro devolve isto.

```json
{
  "sentados": [
    {"amigo": "joao", "linha": 0, "coluna": 2},
    {"amigo": "bevi", "linha": 1, "coluna": 1}
  ],
  "status": [
    {"amigo": "arthur", "status": "pendente"},
    {"amigo": "joao", "status": "ok"},
    {"amigo": "mayara", "status": "pendente"},
    {"amigo": "bevi", "status": "ok"}
  ],
  "venceu": false
}
```

- `sentados` **inclui os fixos**.
- `status`: `ok` (✅), `violada` (❌) ou `pendente` (o amigo, ou alguém que a
  mania dele cita, ainda não sentou).

## Rotas

### `POST /api/fase/nova`

Pedido: `{"dificuldade": "facil"}` (`facil`, `medio` ou `dificil`).
Resposta: uma **Fase**.

A fase é sorteada pelo `generate/4` do `bce.pl` (#6) e tem solução única.
O tamanho depende da dificuldade:

| `dificuldade` | Mesa | Amigos |
|---|---|---|
| `facil` | 2x3 | 4 |
| `medio` | 3x3 | 5 |
| `dificil` | 3x4 | 7 |

### `POST /api/fase/estado`

Pedido: `{"fase": Fase, "sentados": [Lugar]}`. Resposta: um **Estado**.

Serve para mostrar ✅/❌ no começo da fase e quando o jogador **levanta** um
amigo: o Elm tira o amigo de `sentados` e pergunta o novo estado.

### `POST /api/fase/jogada`

Pedido: `{"fase": Fase, "sentados": [Lugar], "amigo": "joao", "linha": 0,
"coluna": 2}`. Resposta: o **Estado** depois de sentar o amigo.

### `POST /api/fase/dica`

Pedido: `{"fase": Fase, "sentados": [Lugar]}`. Resposta:

```json
{"amigo": "mayara", "linha": 0, "coluna": 0,
 "motivo": {"amigo": "mayara", "tipo": "longe_de", "alvo": "joao"}}
```

`motivo` é a mania que força a jogada, no mesmo formato de **Mania**. O Elm
monta a frase ("A Mayara não pode ficar perto do João..."), assim o texto
fica num lugar só. Quando nenhuma mania é necessária (a cadeira sobra por
eliminação, só pela mesa), `motivo` é `null`.

No Prolog, `bce_api:dica/7` chama o `hint/4`, que devolve
`[sentar, Amigo, Linha, Coluna, Dono]`, `[completo]` ou `[sem_solucao]`.
`Dono` é o amigo da mania que força a jogada, ou o átomo `nenhuma` (vira
`motivo: null`). Se o `hint/4` falhar, nenhuma jogada é obrigatória: isso
só acontece numa fase com mais de uma solução.

### `POST /api/fase/resolver`

Pedido: `{"fase": Fase, "sentados": [Lugar]}`. Resposta: um **Estado** com
todo mundo sentado, a partir dos sentados atuais (`solve/4`).

## Erros

Como no Sudoku, todo erro volta como **HTTP 422** com uma mensagem pronta
para a tela em `detail`:

| Quando | `detail` |
|---|---|
| JSON fora do formato (campo faltando, dificuldade desconhecida, coordenada negativa) | erro padrão do FastAPI (`detail` é uma lista) |
| Estado impossível: amigo ou objeto desconhecido, fixo fora do lugar, duas pessoas na mesma cadeira | `"Este estado não existe no jogo. ..."` |
| Jogada não permitida: cadeira ocupada ou fora da mesa, amigo já sentado ou fora da fase | `"Essa jogada não é permitida: ..."` |
| Dica com todos sentados | `"Todo mundo já está sentado."` |
| Dica ou resolver sem solução a partir dos sentados atuais | `"Não dá para terminar a fase a partir daqui. ..."` |
| Dica quando nenhuma jogada é obrigatória | `"Nenhuma jogada é obrigatória agora: mais de uma cadeira serve."` |

Uma jogada que deixa alguma mania ❌ **não** é erro: ela é aceita e aparece
como `violada` no status.
