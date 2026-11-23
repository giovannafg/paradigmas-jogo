module MainTest exposing (suite)

import Api
import Bce exposing (Amigo(..), Estrelas(..), Objeto(..), Rodada(..), Selecao(..))
import Expect
import Main exposing (Acao(..), Consulta(..), Desfecho(..), Msg(..), Tela(..), init, update)
import Test exposing (Test, describe, test)


fase : Bce.Fase
fase =
    { linhas = 2
    , colunas = 3
    , objetos = [ ( Tomada, Bce.Posicao 0 2 ) ]
    , amigos = [ Bevi, Joao, Mayara ]
    , fixos = [ Bce.Lugar Bevi (Bce.Posicao 1 1) ]
    , manias = []
    }


estadoInicial : Api.Estado
estadoInicial =
    { sentados = fase.fixos, status = [], venceu = False }


estadoComJoao : Api.Estado
estadoComJoao =
    { estadoInicial | sentados = fase.fixos ++ [ Bce.Lugar Joao dica.posicao ] }


estadoFinal : Api.Estado
estadoFinal =
    { estadoInicial
        | sentados = fase.fixos ++ [ Bce.Lugar Joao dica.posicao ]
        , venceu = True
    }


dica : Bce.Dica
dica =
    Bce.Dica Joao (Bce.Posicao 0 2) Nothing


suite : Test
suite =
    let
        inicial =
            init { darkTheme = False } |> Tuple.first

        pronto =
            inicial
                |> update (RecebeuFase Api.Facil (Ok fase))
                |> Tuple.first
                |> update (RecebeuEstado (FaseNova Api.Facil fase) (Ok estadoInicial))
                |> Tuple.first

        passar mensagens =
            List.foldl (\msg model -> update msg model |> Tuple.first) pronto mensagens

        pedirDica =
            AcaoJogo PedirDica

        dicaRecebida =
            [ pedirDica, RecebeuDica (Ok dica) ]

        selecionar =
            AcaoJogo (Selecionar Joao)

        sentar =
            AcaoJogo (AtivarCadeira dica.posicao)

        -- Senta e levanta o João: a jogada tira a dica da tela e libera
        -- o botão para pedir a próxima.
        jogarEDesfazer =
            [ selecionar
            , sentar
            , RecebeuEstado (Jogada Joao dica.posicao) (Ok estadoComJoao)
            , sentar
            , RecebeuEstado (Levantada Joao NadaSelecionado) (Ok estadoInicial)
            ]

        comPartida conferir model =
            case model.tela of
                PartidaAberta partida ->
                    conferir partida

                Inicio ->
                    Expect.fail "A fase ainda está carregando"

                FalhaInicial erro ->
                    Expect.fail erro

        vitoria ( quantidade, estrelas ) =
            test ("vitória com " ++ String.fromInt quantidade ++ " dicas") <|
                \_ ->
                    passar
                        (List.concat (List.repeat quantidade (dicaRecebida ++ jogarEDesfazer))
                            ++ [ selecionar, sentar, RecebeuEstado (Jogada Joao dica.posicao) (Ok estadoFinal) ]
                        )
                        |> comPartida
                            (\partida ->
                                Expect.equal ( Rodada (Venceu estrelas), Nothing )
                                    ( partida.desfecho, partida.dica )
                            )
    in
    describe "Tela da Mesa da BCE"
        (List.map vitoria [ ( 0, TresEstrelas ), ( 1, DuasEstrelas ), ( 2, DuasEstrelas ), ( 3, UmaEstrela ) ]
            ++ [ test "falha inicial permite pedir outra fase" <|
                    \_ ->
                        let
                            falhou =
                                update (RecebeuFase Api.Facil (Err "Falha de rede")) inicial |> Tuple.first

                            nova =
                                update (AcaoJogo (NovaFase Api.Medio)) falhou |> Tuple.first
                        in
                        Expect.equal ( FalhaInicial "Falha de rede", Inicio, True )
                            ( falhou.tela, nova.tela, nova.aguardando )
               , test "dica conta uma vez e preserva os assentos" <|
                    \_ ->
                        passar dicaRecebida
                            |> comPartida
                                (\partida ->
                                    Expect.equal ( 1, Just dica, estadoInicial )
                                        ( partida.dicasUsadas, partida.dica, partida.estado )
                                )
               , test "dica na tela bloqueia novo pedido até a próxima jogada" <|
                    \_ ->
                        let
                            model =
                                passar (dicaRecebida ++ [ pedirDica ])
                        in
                        model
                            |> comPartida
                                (\partida ->
                                    Expect.equal ( 1, False )
                                        ( partida.dicasUsadas, model.aguardando )
                                )
               , test "levantar alguém com outro amigo selecionado mostra um aviso" <|
                    \_ ->
                        passar
                            (List.take 3 jogarEDesfazer
                                ++ [ AcaoJogo (Selecionar Mayara)
                                   , sentar
                                   , RecebeuEstado (Levantada Joao (AmigoSelecionado Mayara)) (Ok estadoInicial)
                                   ]
                            )
                            |> comPartida
                                (\partida ->
                                    Expect.equal
                                        ( NadaSelecionado, Just "Você levantou o João e desfez a seleção da Mayara. A cadeira estava ocupada; selecione um amigo de novo para sentá-lo." )
                                        ( partida.selecao, partida.aviso )
                                )
               , test "levantar sem seleção não mostra aviso" <|
                    \_ ->
                        passar (List.take 3 jogarEDesfazer ++ [ sentar, RecebeuEstado (Levantada Joao NadaSelecionado) (Ok estadoInicial) ])
                            |> comPartida (\partida -> Expect.equal Nothing partida.aviso)
               , test "erro de dica aparece e não conta" <|
                    \_ ->
                        passar [ pedirDica, RecebeuDica (Err "Sem solução") ]
                            |> comPartida
                                (\partida ->
                                    Expect.equal ( 0, Nothing, Just "Sem solução" )
                                        ( partida.dicasUsadas, partida.dica, partida.erro )
                                )
               , test "erro de jogada preserva estado e seleção para corrigir" <|
                    \_ ->
                        passar [ selecionar, sentar, RecebeuEstado (Jogada Joao dica.posicao) (Err "Jogada inválida") ]
                            |> comPartida
                                (\partida ->
                                    Expect.equal ( estadoInicial, AmigoSelecionado Joao, Just "Jogada inválida" )
                                        ( partida.estado, partida.selecao, partida.erro )
                                )
               , test "fixo não é levantado nem dispara requisição" <|
                    \_ ->
                        let
                            model =
                                passar [ AcaoJogo (AtivarCadeira (Bce.Posicao 1 1)) ]
                        in
                        model
                            |> comPartida
                                (\partida ->
                                    Expect.equal ( estadoInicial, False )
                                        ( partida.estado, model.aguardando )
                                )
               , test "ações de jogo são ignoradas durante uma requisição" <|
                    \_ ->
                        Expect.equal
                            (passar [ pedirDica ])
                            (passar [ pedirDica, selecionar, AcaoJogo (NovaFase Api.Dificil) ])
               , test "recomeçar limpa a dica e mantém a fase após confirmação" <|
                    \_ ->
                        passar
                            (dicaRecebida
                                ++ [ selecionar, sentar, RecebeuEstado (Jogada Joao dica.posicao) (Ok estadoFinal), AcaoJogo Recomecar, RecebeuEstado Reinicio (Ok estadoInicial) ]
                            )
                            |> comPartida
                                (\partida ->
                                    Expect.all
                                        [ \p -> Expect.equal fase p.fase
                                        , \p -> Expect.equal estadoInicial p.estado
                                        , \p -> Expect.equal ( 0, Nothing, Rodada Jogando ) ( p.dicasUsadas, p.dica, p.desfecho )
                                        ]
                                        partida
                                )
               , test "falha ao trocar de fase mantém a anterior" <|
                    \_ ->
                        passar [ AcaoJogo (NovaFase Api.Dificil), RecebeuFase Api.Dificil (Err "Falha de rede") ]
                            |> comPartida
                                (\partida ->
                                    Expect.equal ( Api.Facil, estadoInicial, Just "Falha de rede" )
                                        ( partida.dificuldade, partida.estado, partida.erro )
                                )
               , test "solução automática encerra a partida com o tabuleiro resolvido" <|
                    \_ ->
                        passar (dicaRecebida ++ [ AcaoJogo Resolver, RecebeuEstado Solucao (Ok estadoFinal) ])
                            |> comPartida
                                (\partida ->
                                    Expect.equal ( Resolvida, estadoFinal, Nothing )
                                        ( partida.desfecho, partida.estado, partida.dica )
                                )
               ]
        )
