# Como contribuir

Combinados do grupo (issue #3). São curtos de propósito: leia antes do
primeiro commit.

## 1. Uma branch por issue

Antes de começar, **se atribua à issue** (*Assignees → assign yourself*) para
ninguém fazer a mesma coisa em dobro. Depois:

```sh
git switch main
git pull
git switch -c <numero>-<descricao-curta>   # ex.: git switch -c 12-tipos-elm
```

Nunca commite direto na `main`.

## 2. Pull request para a `main`

- Abra o PR assim que tiver algo para mostrar (pode ser *draft*).
- Na descrição, escreva `Closes #N` para a issue fechar sozinha no merge.
- Diga o que mudou e como testar.
- Se usou IA, declare no PR (ver seção 6).

## 3. Revisão

- **Pelo menos 1 colega aprova antes do merge.** Quem abriu o PR não faz o
  merge sem essa aprovação.
- Quem revisa roda o código: `make test` e, se mexeu na tela, `make dev`.
- Prefira revisar alguém da sua dupla natural (ver #20): quem mexe no mesmo
  `.pl`, no mesmo formato de JSON ou nos mesmos tipos do Elm.
- Mantenha a branch atualizada com a `main` antes do merge
  (`git pull origin main`).

## 4. Antes de commitar

O critério 4 da nota (qualidade) é medido por script. Rode:

```sh
make test                                    # testes Prolog e Python passando
cd frontend && npx elm-format src/ --yes     # formata todo o Elm
swipl -g halt backend/prolog/<arquivo>.pl    # tem que carregar SEM avisos
```

- **`elm-format` sempre.** Código Elm sem formatação perde ponto.
- **`swipl` sem avisos:** nada de *singleton variables*, cláusulas
  separadas (*discontiguous*) ou predicados sem definição.
- Não deixe código morto, `Debug.log` ou trechos comentados.
- Comentários explicam **por que**, não repetem o que o código faz.
- O Python é **só ponte**: lógica do jogo fica no Prolog, estado e tela
  ficam no Elm.

## 5. Cada um commita com a própria conta

O professor compara os commits por autor com a seção 10 do relatório e com a
avaliação 360. Confira se o git está com o **seu** nome e e-mail do GitHub:

```sh
git config user.name
git config user.email
```

Em programação em dupla, quem não está no teclado entra como coautor na
última linha da mensagem do commit:

```
Co-authored-by: Nome Sobrenome <email-do-github@exemplo.com>
```

## 6. Uso de IA tem que ser declarado

Uso de IA é permitido, mas **uso não declarado zera o trabalho de todo o
grupo** (`AVALIACAO.md`, seção 1.3).

- Quem usar escreve no PR: **qual ferramenta** e **para quê** (ex.: "Claude
  para gerar o esqueleto dos decoders; revisei e escrevi os testes").
- Essas anotações vão para a tabela da seção 11 do `RELATORIO.md`.
- Entenda cada linha que você entregar: na apresentação, o professor pede
  para você explicar o código que o relatório atribui a você.

## Mensagens de commit

Seguimos o padrão [Conventional Commits](https://www.conventionalcommits.org/pt-br/v1.0.0/):

```
<tipo>(<escopo opcional>): <descrição>
```

A descrição é em português, no imperativo, curta e sem ponto final.

| Tipo | Quando usar |
|---|---|
| `feat` | funcionalidade nova (mania, rota, tela) |
| `fix` | correção de bug |
| `style` | só formatação, sem mudar comportamento (ex.: `elm-format`) |
| `refactor` | reorganiza o código sem mudar comportamento |
| `test` | adiciona ou corrige testes (plunit, pytest) |
| `docs` | documentação (`REGRAS.md`, `RELATORIO.md`, README) |
| `chore` | configuração, dependências, scripts, tarefas de manutenção |

Escopos sugeridos: `prolog`, `elm`, `api`, `css`, `relatorio`.

```
feat(prolog): adiciona mania sem_vizinhos ao interpretador
fix(elm): corrige decoder da dica quando a fase já terminou
style(elm): aplica elm-format em Main.elm
test(prolog): cobre fase sem solução no solve
docs: descreve as regras do jogo em REGRAS.md
```
