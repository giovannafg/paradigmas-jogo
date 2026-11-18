# Mesa da BCE — Prolog + Elm

Jogo do trabalho final de Paradigmas de Programação. É véspera de prova e os
7 integrantes do grupo vão estudar juntos numa mesa da BCE. Cada um tem uma
mania para estudar, e o jogador precisa sentar todo mundo respeitando todas
as manias ao mesmo tempo. As regras completas estão em
[docs/REGRAS.md](docs/REGRAS.md).

O Prolog é o cérebro: ele descreve as manias como restrições, valida as
jogadas, dá dicas, resolve e gera fases novas. O Elm desenha a interface. O
Python só faz a ponte entre os dois.

```
┌──────────────────────┐   HTTP/JSON   ┌───────────────────┐  janus  ┌──────────────────┐
│ Navegador            │ ────────────▶ │ FastAPI (Python)  │ ──────▶ │ SWI-Prolog       │
│ Elm + daisyUI (Vite) │ ◀──────────── │ backend/app/      │ ◀────── │ backend/prolog/  │
└──────────────────────┘               └───────────────────┘         └──────────────────┘
    avaliado                              NÃO avaliado                  avaliado
```

## O que cada parte faz

**Prolog** (`backend/prolog/`). `bce.pl` tem as regras: cada mania é um fato
`mania/2`, traduzido em restrições com a biblioteca CLP(FD), e o resolvedor
de restrições acha as respostas. Os predicados principais:

- `restricoes/4` traduz a mesa e as manias em restrições sobre as cadeiras;
- `status_manias/4` diz como está cada mania (respeitada, violada ou
  pendente) e `venceu/3` decide se a fase acabou;
- `estado_valido/3` e `jogada_valida/5` recusam estados e jogadas que não
  existem no jogo;
- `solve/4` completa a mesa a partir de quem já está sentado;
- `hint/4` acha uma jogada obrigatória e a mania que a força;
- `generate/4` sorteia uma fase com solução única, no nível `facil`, `medio`
  ou `dificil`.

`bce_api.pl` é uma casca fina em volta do `bce.pl`: converte as strings que
vêm do JSON nos átomos e termos que o `bce.pl` espera, e devolve o resultado
numa forma que o janus sabe entregar ao Python. Assim o `bce.pl` não precisa
saber que existe uma API.

**Python** (`backend/app/`). `prolog.py` carrega o `bce_api.pl` com a
biblioteca [janus](https://www.swi-prolog.org/pldoc/man?section=janus), que
roda o SWI-Prolog dentro do próprio processo Python. `main.py` expõe os
predicados como rotas HTTP com o FastAPI. Não há lógica de jogo aqui.

**Elm** (`frontend/src/`). Segue a Arquitetura Elm (Model, Msg, update, view).

- `Bce.elm` guarda os tipos do domínio (amigos, objetos, manias, posições) e
  as regras que precisam ser instantâneas, como recusar uma cadeira ocupada.
  Não faz HTTP nem HTML.
- `Api.elm` faz as requisições e converte JSON em valores Elm.
- `Main.elm` cuida do estado da partida, dos eventos e da tela.

O formato do JSON trocado entre as três camadas está em
[docs/API.md](docs/API.md).

O visual fica todo em `frontend/src/style.css`. O Elm usa classes semânticas
(`bce-mesa`, `bce-cadeira`, `bce-nivel--ativo`), e o CSS as define com o
`@apply` do [Tailwind](https://tailwindcss.com) e os componentes do
[daisyUI](https://daisyui.com). O [Vite](https://vite.dev) serve o frontend e
recompila o Elm a cada vez que você salva um arquivo.

O código está cheio de comentários explicando construções de cada linguagem.

## Requisitos

- [SWI-Prolog](https://www.swi-prolog.org/Download.html) 9.2 ou mais novo
  (o comando `swipl` precisa estar no PATH);
- [uv](https://docs.astral.sh/uv/) para o Python (ele instala o Python certo
  sozinho);
- [Node.js](https://nodejs.org) 20 ou mais novo, com `npm`.

O compilador do Elm é instalado pelo `npm`, dentro de `frontend/node_modules`.
Não precisa instalar nada globalmente.

No Debian/Ubuntu, a versão do SWI-Prolog no `apt` pode ser antiga. O PPA
oficial resolve: `sudo add-apt-repository ppa:swi-prolog/stable`. Se o
`uv sync` falhar ao instalar o `janus-swi`, quase sempre é porque ele não
achou o `swipl`. Confira com `swipl --version`.

## Como rodar

```sh
make install    # instala as dependências (uma vez só)
make dev        # sobe backend e frontend
```

Abra http://localhost:5173. A documentação interativa da API fica em
http://localhost:8000/docs, e dá para testar as rotas por lá.

Sem `make`, abra dois terminais:

```sh
# terminal 1
cd backend
uv sync
uv run fastapi dev app/main.py

# terminal 2
cd frontend
npm install
npm run dev
```

Os dois servidores recarregam sozinhos quando você salva um arquivo. O Vite
repassa tudo que começa com `/api` para o backend na porta 8000 (veja
`frontend/vite.config.js`).

## Mudando o visual

Abra `frontend/src/style.css` e procure a seção **4. VARIÁVEIS DE
PERSONALIZAÇÃO**. Dá para mudar muita coisa só trocando valores, sem
escrever CSS novo:

- a fonte do título;
- a largura da mesa e da coluna dos amigos;
- o gradiente do fundo, a intensidade do granulado e da grade de pontos;
- o efeito de vidro dos painéis.

As cores principais vêm dos temas `light` e `dark` do daisyUI, com as cores
redefinidas na seção 2.
O botão sol/lua do cabeçalho troca entre eles com o `theme-controller` do
daisyUI, que funciona só com CSS. Na primeira visita vale a preferência do
sistema operacional; depois, o `main.js` guarda a escolha no `localStorage`
e a entrega ao Elm como *flag* na inicialização.
Para trocar uma fonte, instale outra do [Fontsource](https://fontsource.org)
(`npm install @fontsource-variable/NOME`) e troque o `@import`
correspondente na seção 1.

## Brincando com o Prolog direto no terminal

Não precisa do resto do sistema para testar o Prolog:

```
$ swipl backend/prolog/bce.pl
?- generate(facil, Mesa, Amigos, Fixos).
?- fase_exemplo(M, A, S), solve(M, A, S, Solucao).
?- fase_exemplo(M, A, S), hint(M, A, S, Dica).
```

Esse é o jeito mais rápido de desenvolver a parte lógica. Só depois de o
predicado funcionar no `swipl` vale a pena ligá-lo ao Python.

## Problemas comuns

**`ImportError: libswipl.so.9: cannot open shared object file`** ao subir o
backend ou rodar os testes. O pacote `janus-swi` é compilado contra uma versão
específica do SWI-Prolog. Seu sistema pode ter algum problema de compatibilidade
que necessita de compilação manual. Recompile o pacote a partir do código-fonte,
ignorando o cache:

```sh
cd backend
uv sync --reinstall-package janus-swi --no-binary-package janus-swi --no-cache
```

## Testes

```sh
make test           # tudo
make test-prolog    # só os testes em Prolog (plunit)
make test-backend   # só os testes da API (pytest)
make test-frontend  # só os testes do Elm (elm-test)
```

## API

Todas as rotas são `POST` e recebem e devolvem JSON. O formato completo, com
exemplos de cada corpo e resposta, está em [docs/API.md](docs/API.md).

| Rota                     | Para que serve                                      |
| ------------------------ | --------------------------------------------------- |
| `POST /api/fase/nova`    | sorteia uma fase nova no nível pedido               |
| `POST /api/fase/estado`  | status das manias de quem está sentado              |
| `POST /api/fase/jogada`  | senta um amigo numa cadeira                         |
| `POST /api/fase/dica`    | uma jogada obrigatória e a mania que a força         |
| `POST /api/fase/resolver`| completa a mesa a partir de quem já está sentado     |

Quando a jogada ou o estado não existem no jogo, a resposta é 422 com
`{"detail": "mensagem"}`. O Elm mostra essa mensagem na tela.

## Entrega

A entrega acontece pelo GitHub Classroom, em duas atividades:

1. **Repositório do grupo.** Um por grupo, com o código do projeto e o
   `RELATORIO.md` preenchido. Este arquivo é o template do relatório:
   preencha todas as seções (as instruções estão em comentários dentro do
   próprio arquivo e não aparecem quando ele é visualizado).
2. **Repositório individual.** Um por aluno, com a avaliação 360 graus dos
   colegas em `avaliacao-360/<sua-matricula>.md`, copiada de
   `avaliacao-360/TEMPLATE.md`. Esse repositório pode partir deste template
   ou do código final do grupo, tanto faz. Só você e o professor leem o que
   está nele.

Antes de entregar, confira a forma dos documentos com o validador:

```sh
make validar                                                # repositório do grupo
uv run scripts/validar_entrega.py avaliacao-360/<matricula>.md   # repositório individual
```

Ele aponta comentários de instrução que sobraram, campos entre colchetes não
preenchidos, tabelas malformadas, seções e subseções faltando, arquivos
citados que não existem, notas fora da escala, divisões de esforço que não
somam 100%, roteiro da apresentação acima de 15 minutos e integrantes que
aparecem numa tabela e não em outra. Também avisa quando um colega recebeu
nota 1, 2 ou 5 e ficou sem comentário. Erros impedem a entrega; avisos
merecem uma conferida.

Os critérios de avaliação, com a rubrica da nota do grupo, a fórmula da
nota individual e os prazos (18/11 sem desconto; 23/11 e 30/11 com
desconto), estão em `AVALIACAO.md`.

### Ferramentas do professor

Os scripts em `scripts/` cobrem a correção de ponta a ponta: baixar as
entregas do GitHub Classroom, fazer a triagem de código suspeito, medir,
preencher a rubrica e agregar as avaliações 360 em notas. Os alunos não
precisam deles. O fluxo e o uso de cada um estão em `scripts/README.md`.

## Estrutura

```
backend/
  prolog/bce.pl           regras, validação, dica, resolvedor e gerador
  prolog/bce_api.pl       converte o JSON em átomos e termos do bce.pl
  prolog/test_bce.pl      testes plunit
  app/prolog.py           ponte Python → Prolog (janus)
  app/main.py             rotas HTTP (FastAPI)
  tests/test_api_bce.py   testes da API
frontend/
  src/Main.elm            Arquitetura Elm: estado, eventos, tela
  src/Bce.elm             tipos e regras do domínio
  src/Api.elm             HTTP e JSON
  src/main.js             inicia o Elm e lembra o tema escolhido
  src/style.css           visual: temas, variáveis, componentes
  tests/                  testes do Elm (elm-test)
  vite.config.js          plugins e proxy para o backend
docs/REGRAS.md            as regras do jogo e as manias de cada integrante
docs/API.md               formato do JSON entre Elm, Python e Prolog
Makefile                  atalhos (install, dev, test, validar)
RELATORIO.md              relatório de entrega
AVALIACAO.md              critérios de avaliação (rubrica e nota individual)
avaliacao-360/TEMPLATE.md template da avaliação 360 graus (individual)
scripts/validar_entrega.py valida a forma dos documentos de entrega
scripts/                  (professor) baixar, auditar, medir, rubrica, agregar;
                          veja scripts/README.md
```
