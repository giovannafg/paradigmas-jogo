# Regras do jogo: Mesa da BCE

> Nome do projeto: **Mesa da BCE**. Nome do grupo: **a definir** (#1).
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
- Algumas cadeiras têm um **objeto fixo**: 🪟 janela, 🔌 tomada, 🚪 porta,
  📚 estante. O objeto está *naquela cadeira*.
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
   sentá-lo. Clicar num amigo já sentado o devolve para o lado da mesa.
2. A cada jogada, cada mania aparece como ✅ (respeitada) ou ❌ (violada).
   Manias que dependem de alguém que ainda não sentou ficam neutras.
3. **Vitória:** todos os amigos da fase sentados e todas as manias ✅.
4. **Dica:** o jogador pode pedir uma dica, que explica **um** passo do
   raciocínio sem entregar a fase inteira.
5. **Estrelas** (proposta): ⭐⭐⭐ sem dicas, ⭐⭐ com 1 ou 2 dicas, ⭐ com 3
   ou mais.

## O que o Prolog faz

O Prolog é o cérebro do jogo. O Python só repassa as requisições.

- **Base de conhecimento:** o mapa da mesa (`objeto(tomada, 0, 2)`), os
  amigos da fase e as manias (`mania/2`).
- **Resolver (`solve`):** um interpretador transforma cada fato `mania/2` em
  restrições CLP(FD) sobre a posição de cada amigo, e a busca encontra o
  arranjo que satisfaz todas.
- **Gerar (`generate`):** escolhe o tamanho da mesa, quais amigos entram,
  onde ficam os objetos e quem já começa sentado. Só aceita a fase quando
  existe **exatamente uma** solução, para que ela sempre possa ser resolvida
  só com raciocínio, sem chute.
- **Dica (`hint`):** encontra um amigo cuja cadeira já é forçada pelo estado
  atual e **explica qual mania força** essa jogada.
- **Validar jogada:** diz quais manias estão ✅ ou ❌ no tabuleiro atual.

### Por que existem amigos já sentados

Testamos por força bruta todas as fases possíveis em mesas 2x3, 2x4 e 3x3
só com as manias acima, e **nenhuma tem solução única**. As manias são
simétricas: espelhar a mesa ou trocar dois amigos de lugar quase sempre gera
outra solução válida. Para que a solução seja única, o gerador precisa de
pelo menos uma "âncora", como acontece no Sudoku com os números iniciais.
O gerador (#6) usa **amigos já sentados**: fixa amigos da solução até ela
ficar única e depois tira os que não fazem falta.

## Exemplo de fase (mesa 2x3)

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

Uma dica possível no passo 3: *"A Mayara não pode ficar perto do João. Na
fileira de cima, só a ponta da esquerda fica longe dele."*

## Dificuldade

- **Fácil:** 3 ou 4 amigos, mesa pequena, manias diretas (objetos).
- **Difícil:** até os 7 amigos, mesa maior, manias que só se resolvem
  combinadas (ex.: a da Mayara junto com a do Bevi).
- **Extra, se der tempo:** medir a dificuldade pelo número de passos de
  dedução, e um editor de manias em que o Prolog diz se a fase continua
  possível ou quais regras entram em conflito.

## O que a tela mostra (Elm)

- A mesa como grade, com os ícones dos objetos e os amigos sentados (os já
  sentados aparecem travados).
- Os cards dos amigos, cada um com a mania e o status ✅ ou ❌.
- Botões **Nova fase** (com dificuldade), **Dica** e **Recomeçar**.
- A explicação da dica e as mensagens de erro da API.
- A tela de vitória com as estrelas.

Tipos previstos: `type Amigo = Arthur | Bevi | Felipe | Gabriel | Giovanna |
Joao | Mayara`, `type Objeto = Janela | Tomada | Porta | Estante`,
`type Mania = PertoDeObjeto Objeto | NaCadeiraDe Objeto | SemVizinhos |
DeFrentePara (List Amigo) | PertoDe Amigo | LadoALadoCom Amigo | LongeDe Amigo`, `type Fase = Jogando ... | Venceu Estrelas`.

## MVP

4 amigos, os 7 tipos de mania acima, mesa até 3x3, e as funções gerar,
resolver e dar dica. O resto vem depois.

## Pontos em aberto

- [x] Mania da Giovanna: lado a lado com a Mayara.
- [x] Nome do projeto: Mesa da BCE.
- [ ] Nome do grupo.
- [x] "Do lado da tomada" do João: **exatamente na cadeira** da tomada.
- [x] "Perto da porta" do Arthur: **inclui** a própria cadeira da porta
      (regra geral de "perto de um objeto", acima; no Prolog, `perto_ou_na`).
- [x] Âncora do gerador: **amigos já sentados** (#6).
- [ ] 🪟 janela e 📚 estante ainda não aparecem em nenhuma mania. Hoje o
      gerador põe porta, tomada e uma janela ou estante sorteada, só como
      decoração. Manter assim, ou alguém troca a mania para usá-las? Se
      trocar, muda o `mania/2` no `bce.pl` e os testes do Prolog; a API e o
      Elm continuam iguais.
- [ ] Regra das estrelas: contar só dicas, ou também jogadas que deixam
      alguma mania ❌? Hoje o `estrelasPorDicas` do `Bce.elm` (#10) conta só
      dicas, como na proposta da regra 5.
