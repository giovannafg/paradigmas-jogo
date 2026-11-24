# Regras do jogo: Mesa da BCE

> Nome do projeto: **Mesa da BCE**. Nome do grupo: **Os Sem Agenda**.
> Ideia proposta pela Giovanna e escolhida por todos na issue #1.

## Premissa

É véspera de prova e os 7 integrantes do grupo vão estudar juntos numa mesa
da BCE. Cada um tem uma mania para estudar. O jogador precisa **colocar cada
amigo numa cadeira** de um jeito que todas as manias sejam respeitadas ao
mesmo tempo.

## Ponto de partida

**Jogo inventado pelo grupo** (faixa de +1,0 em `AVALIACAO.md`, seção 1.5).
As regras e as manias são nossas. Do template do Sudoku aproveitamos só a
estrutura: servidor Python, integração Prolog ↔ API e arquitetura Elm.

## O tabuleiro

- A mesa é uma **grade de cadeiras** com `L` linhas e `C` colunas (ex.: 2x3).
- Algumas cadeiras têm um **objeto fixo**: 🚪 porta, 🔌 tomada e uma
  decoração (🪟 janela ou 📚 estante). O objeto está *naquela cadeira*.
  Nas fases sorteadas, a porta fica sempre na cadeira do canto de cima à
  direita; a tomada e a decoração são sorteadas entre as outras.
- A decoração não aparece em nenhuma mania nem é desenhada na tela: ela só
  ocupa espaço no modelo, para que novas manias possam usá-la sem mudar a
  API nem o Elm.
- A fase pode começar com **amigos já sentados**, que não podem ser movidos,
  como os números fixos do Sudoku (ver "Por que existem amigos já sentados").
- Ao lado da mesa ficam os **cards dos amigos** que entram na fase, cada um
  com a sua mania.
- Pode sobrar cadeira vazia.

### Vocabulário de posição

Todas as manias usam estas três relações entre duas cadeiras:

| Relação | Significado |
|---|---|
| **lado a lado** | mesma linha, colunas vizinhas (esquerda ou direita) |
| **de frente** | mesma coluna, linhas vizinhas (em cima ou embaixo) |
| **perto** | qualquer uma das até 8 cadeiras ao redor, incluindo as diagonais |

"Perto de um objeto" vale para a própria cadeira do objeto ou para qualquer
cadeira perto dela.

## As manias

Cada integrante escolheu a sua na issue #1:

| Amigo | Mania (como foi escrita) | Regra formal | Fato em Prolog (`backend/prolog/bce.pl`) |
|---|---|---|---|
| Arthur (`artrsousa1`) | "Gosta de dar uma passeada de vez em quando, então prefere sentar perto da porta" | Arthur fica **perto** da 🚪 | `mania(arthur, perto_de_objeto(porta))` |
| Bevi (`gbevi`) | "Ninguém pode sentar lado a lado com o Bevi" | nenhuma cadeira **lado a lado** com o Bevi pode estar ocupada | `mania(bevi, sem_vizinhos)` |
| Felipe (`darkymeubem`) | "Preciso sentar de frente para o Arthur (ou João) para tirar dúvidas da matéria" | Felipe fica **de frente** para o Arthur ou para o João | `mania(felipe, de_frente_para_algum([arthur, joao]))` |
| Gabriel (`GabrielCastelo-31`) | "Prefere sentar perto do Arthur para aprender a programar Pix em Java" | Gabriel fica **perto** do Arthur | `mania(gabriel, perto_de(arthur))` |
| Giovanna (`giovannafg`) | "Mayara e Giovanna estudam juntas: têm que ficar lado a lado" (exemplo da proposta na issue #1) | Giovanna fica **lado a lado** com a Mayara | `mania(giovanna, lado_a_lado_com(mayara))` |
| João (`joaofmoreiraa`) | "Só pode sentar do lado da tomada, pois o celular descarrega rápido" | João senta **na cadeira** da 🔌 | `mania(joao, na_cadeira_de(tomada))` |
| Mayara (`maymarquee`) | "Não pode sentar perto do João, senão os dois só conversam e ninguém estuda" | Mayara **não** fica **perto** do João | `mania(mayara, longe_de(joao))` |

Uma mania só vale se o outro amigo citado estiver na fase. Se o Arthur não
entrar, a mania do Gabriel não restringe nada, e a do Felipe passa a exigir
o João. Do mesmo jeito, se a mesa não tiver o objeto citado (ex.: nenhuma
tomada), a mania é ignorada.

Como as manias são **dados**, adicionar uma nova é adicionar um fato
`mania/2` e, se for um tipo novo, uma cláusula no interpretador que traduz o
fato em restrição CLP(FD).

## Como se joga

1. O jogador clica num card de amigo e depois numa cadeira livre para
   sentá-lo. Clicar numa cadeira ocupada levanta quem está nela (quem já
   começa sentado não sai do lugar).
2. A cada jogada, o Prolog avalia cada mania como respeitada, violada ou
   pendente (depende de alguém que ainda não sentou). O card e a cadeira de
   quem tem a mania violada ficam em vermelho, assim como a cadeira da
   jogada que causou o conflito.
3. **Vitória:** todos os amigos da fase sentados e todas as manias
   respeitadas.
4. **Dica:** o jogador pode pedir uma dica, que mostra **uma** jogada
   obrigatória e a mania que a força, sem entregar a fase inteira. O amigo
   da dica fica destacado em amarelo.
5. **Estrelas:** ⭐⭐⭐ sem dicas, ⭐⭐ com 1 ou 2 dicas, ⭐ com 3 ou mais.
   Quem usa **Resolver** termina a fase sem estrelas.

## O que o Prolog faz

O Prolog é o cérebro do jogo (`backend/prolog/bce.pl`). O Python só repassa
as requisições: o `bce_api.pl` traduz o JSON para os termos do `bce.pl`, e
as rotas estão em `docs/API.md`.

- **Base de conhecimento:** os amigos (`amigo/1`), os objetos (`objeto/1`) e
  as manias (`mania/2`). A mesa é o termo `mesa(Linhas, Colunas, Objetos)`,
  com cada objeto na sua cadeira, como `[tomada, 0, 2]`.
- **Resolver (`solve/4`):** um interpretador transforma cada fato `mania/2`
  em restrições CLP(FD) sobre a posição de cada amigo, e a busca encontra o
  arranjo que satisfaz todas.
- **Gerar (`generate/4`):** a partir do nível, sorteia os amigos e coloca a
  porta, a tomada e uma janela ou estante. Só aceita a fase quando existe
  **exatamente uma** solução (`count_solutions/5`), para que ela sempre
  possa ser resolvida só com raciocínio, sem chute.
- **Dica (`hint/4`):** encontra um amigo cuja cadeira já é forçada pelo
  estado atual e **diz qual mania força** essa jogada. Quando a cadeira
  sobra só por eliminação, a dica não cita mania.
- **Validar:** `estado_valido/3` recusa estados impossíveis (amigo
  desconhecido, duas pessoas na mesma cadeira, mesa fora de 1x1 a 6x6),
  `jogada_valida/5` confere a jogada, `status_manias/4` diz se cada mania
  está ✅, ❌ ou pendente e `venceu/3` confere a vitória.

### Por que existem amigos já sentados

Testamos por força bruta todas as fases possíveis em mesas 2x3, 2x4 e 3x3
só com as manias acima, e **nenhuma tem solução única**. As manias são
simétricas: espelhar a mesa ou trocar dois amigos de lugar quase sempre gera
outra solução válida. Para que a solução seja única, o gerador precisa de
pelo menos uma "âncora", como acontece no Sudoku com os números iniciais.
O gerador usa **amigos já sentados**: fixa amigos da solução até ela
ficar única e depois tira os que não fazem falta.

## Exemplo de fase (mesa 2x3)

Esta é a fase `fase_exemplo/3` do `bce.pl`, usada nos testes plunit. Ela foi
montada à mão, por isso a porta está à esquerda; nas fases sorteadas a porta
fica sempre à direita.

Porta no canto de cima à esquerda, tomada no canto de cima à direita.
Amigos: Arthur, João, Mayara e **Bevi, que já começa sentado** na cadeira de
baixo, no meio.

O raciocínio:

1. Ninguém pode ficar lado a lado com o Bevi, então as duas cadeiras de
   baixo ficam vazias. Arthur, João e Mayara ocupam a fileira de cima.
2. O João precisa sentar na cadeira da tomada: a de cima, à **direita**.
3. A Mayara não pode ficar perto do João. Na fileira de cima, a única
   cadeira longe dele é a ponta oposta: a Mayara fica na **esquerda**.
4. Sobra a cadeira do meio para o Arthur, que fica perto da porta. ✅

```
┌───────┬───────┬───────┐
│ 🚪 M  │   A   │ 🔌 J  │
├───────┼───────┼───────┤
│       │  [B]  │       │
└───────┴───────┴───────┘   Venceu! ⭐⭐⭐
```

Pedindo uma dica no começo, o Prolog (`hint/4`) aponta o passo 2: sentar o
João na linha 1, coluna 3, por causa da mania dele (a cadeira da tomada).

## Dificuldade

O gerador tem três níveis:

| Nível | Mesa | Amigos | Amigos já sentados |
|---|---|---|---|
| Fácil | 2x3 | 4 | até 1 |
| Médio | 3x3 | 5 | até 2 |
| Difícil | 3x4 | 7 | até 3 |

Os amigos de cada fase são sorteados, então as manias que aparecem mudam de
uma fase para outra.

## O que a tela mostra (Elm)

- A mesa como grade de cadeiras, com a porta e a tomada desenhadas e os
  amigos sentados.
- Na coluna da esquerda, os cards dos amigos da fase, cada um com a sua
  mania; em vermelho quando a mania está violada.
- Os botões de nível (**Fácil**, **Médio**, **Difícil**), que sorteiam uma
  fase nova, e os botões **Dica**, **Resolver** e **Recomeçar**.
- Uma janela **Regras do jogo** com o resumo deste documento.
- A explicação da dica, as mensagens de erro da API e o resultado da fase
  ("Você venceu!" com as estrelas, ou "Resolvido com ajuda").
- O botão de modo claro/noturno.

Os tipos estão em `frontend/src/Bce.elm`: `type Amigo = Arthur | Bevi
| Felipe | Gabriel | Giovanna | Joao | Mayara`, `type Objeto = Janela |
Tomada | Porta | Estante`, `type Mania = PertoDeObjeto Objeto | NaCadeiraDe
Objeto | SemVizinhos | DeFrentePara (List Amigo) | PertoDe Amigo |
LadoALadoCom Amigo | LongeDe Amigo`, `type StatusMania = Respeitada |
Violada | Pendente` e `type Rodada = Jogando | Venceu Estrelas`. A `Fase` é
um record com a mesa, os amigos, os fixos e as manias.
