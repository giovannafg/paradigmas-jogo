# Elm na tela do Grupo de Estudo na BCE

A tela da Mesa da BCE está em `Main.elm`. Ela usa os tipos e as funções
puras de `Bce.elm` e as requisições de `Api.elm`. A integração local
combina as rotas do PR #31 com o cliente Elm do PR #32.
[Issue #12](https://github.com/giovannafg/paradigmas-jogo/issues/12),
[backend](https://github.com/giovannafg/paradigmas-jogo/pull/31),
[API Elm](https://github.com/giovannafg/paradigmas-jogo/pull/32)

## Ordem de leitura

1. **Botões.** No exemplo interativo do contador, adicione o botão de zerar.
   Você vai criar um construtor de `Msg`, ligar o botão com `onClick` e
   escrever o ramo correspondente de `update`. Na BCE, um clique pode
   produzir `NovaFase dificuldade` e carregar a dificuldade junto com o
   evento. [Tutorial oficial de botões](https://guide.elm-lang.org/architecture/buttons)
2. **Tipos próprios.** Um `type alias` dá nome a uma estrutura. Um
   `type` enumera as variantes que um valor pode assumir e os dados de
   cada uma. Leia `Rodada` em `Bce.elm`: `Jogando` e
   `Venceu Estrelas` expressam que só uma vitória carrega a nota. Na tela,
   use variantes para representar a fase inicial em carregamento, a falha
   de carregamento e uma fase disponível. Enumere as variantes nos
   `case` de mensagens e estados.
   [Tutorial oficial de tipos próprios](https://guide.elm-lang.org/types/custom_types)
3. **HTTP.** O exemplo do livro usa `Browser.element`. O `update`
   devolve uma tupla com o modelo seguinte e um `Cmd Msg`. O runtime
   executa o comando HTTP e envia outra mensagem com `Ok` ou `Err`.
   Na BCE, a geração devolve a configuração da fase. A consulta de
   estado devolve os assentos, o status das manias e o indicador de
   vitória. Estude os dois retornos separadamente.
   [Tutorial oficial de HTTP](https://guide.elm-lang.org/effects/http)
4. **Teclado.** Os cards disponíveis e as cadeiras interativas são botões
   HTML. Use Tab para navegar e Enter ou Espaço para ativá-los. O navegador
   dispara o evento de clique, então `onClick` produz a mesma mensagem nas
   duas formas de jogar.
   [Especificação de ativação de controles HTML](https://html.spec.whatwg.org/multipage/interaction.html#activation-behavior)

## Exercício no código do projeto

Siga primeiro um botão de dificuldade. O clique produz `AcaoJogo (NovaFase dificuldade)`. O `update` marca o carregamento e devolve o comando
`Api.novaFase dificuldade (RecebeuFase dificuldade)`. A aplicação parcial
`RecebeuFase dificuldade` é a função que transforma um
`Result String Bce.Fase` em `Msg`. No `Ok fase`,
consulte `Api.estado` com os assentos iniciais da fase. No
`Err mensagem`, guarde a mensagem para a `view` mostrar.

Depois siga uma jogada. A seleção identifica um amigo. A cadeira
selecionada identifica a posição. O retorno da API fornece os lugares
e o status das manias. Ao receber `venceu = True`, construa
`Bce.Venceu (Bce.estrelasPorDicas quantidadeDeDicas)`.
No navegador, percorra uma jogada por clique e a mesma ação por
teclado. Compare o estado renderizado e confira o texto de um erro
HTTP. O comentário da issue também sugere chamar `update` diretamente
com as mensagens de resposta para testar as transições.
[Contrato da API](API.md),
[comentário da issue](https://github.com/giovannafg/paradigmas-jogo/issues/12#issuecomment-6859304932)
