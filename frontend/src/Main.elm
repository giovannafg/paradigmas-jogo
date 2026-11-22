module Main exposing (Acao(..), Consulta(..), Desfecho(..), Msg(..), Tela(..), init, main, update)

import Api exposing (Dificuldade(..), Estado)
import Bce exposing (Amigo, Dica, Estrelas(..), Fase, Objeto(..), Posicao, Rodada(..), Selecao(..), StatusMania(..))
import Browser
import Browser.Dom
import Html exposing (Html, button, div, h1, h2, header, img, input, label, main_, p, section, span, text)
import Html.Attributes exposing (attribute, checked, class, classList, disabled, id, src, alt, title, style, type_, value)
import Html.Events exposing (onCheck, onClick)
import Task


type alias Flags =
    { darkTheme : Bool }


type alias Model =
    { tela : Tela
    , darkTheme : Bool
    , aguardando : Bool
    }


type Tela
    = Inicio
    | FalhaInicial String
    | PartidaAberta Partida


type alias Partida =
    { fase : Fase
    , dificuldade : Dificuldade
    , estado : Estado
    , selecao : Selecao
    , desfecho : Desfecho
    , dica : Maybe Dica
    , dicasUsadas : Int
    , conflitoRecente : Maybe Posicao
    , erro : Maybe String
    , aviso : Maybe String
    }


type Desfecho
    = Rodada Rodada
    | Resolvida


type Acao
    = NovaFase Dificuldade
    | Selecionar Amigo
    | AtivarCadeira Posicao
    | PedirDica
    | Resolver
    | Recomecar


{-| A mesma resposta de estado pode iniciar, atualizar ou encerrar a partida.
A consulta identifica a transição que o servidor confirmou.
-}
type Consulta
    = FaseNova Dificuldade Fase
    | Jogada Amigo Posicao
    | Levantada Amigo Selecao
    | Reinicio
    | Solucao


type Msg
    = AcaoJogo Acao
    | RecebeuFase Dificuldade (Result String Fase)
    | RecebeuEstado Consulta (Result String Estado)
    | RecebeuDica (Result String Dica)
    | TemaAlterado Bool
    | DescerPersonagens
    | RecebeuPosicaoPersonagens (Result Browser.Dom.Error Browser.Dom.Viewport)
    | RolagemConcluida


main : Program Flags Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = always Sub.none
        }


init : Flags -> ( Model, Cmd Msg )
init flags =
    update (AcaoJogo (NovaFase Facil))
        { tela = Inicio, darkTheme = flags.darkTheme, aguardando = False }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        AcaoJogo acao ->
            if model.aguardando then
                ( model, Cmd.none )

            else
                executar acao model

        RecebeuFase dificuldade (Ok fase) ->
            ( model, Api.estado fase fase.fixos (RecebeuEstado (FaseNova dificuldade fase)) )

        RecebeuFase _ (Err erro) ->
            ( falhou erro model, Cmd.none )

        RecebeuEstado consulta (Ok estado) ->
            ( { model | aguardando = False, tela = aplicarEstado consulta estado model.tela }
            , Cmd.none
            )

        RecebeuEstado _ (Err erro) ->
            ( falhou erro model, Cmd.none )

        RecebeuDica (Ok dica) ->
            ( { model
                | aguardando = False
                , tela =
                    mapPartida
                        (\partida ->
                            { partida | dica = Just dica, dicasUsadas = partida.dicasUsadas + 1 }
                        )
                        model.tela
              }
            , Cmd.none
            )

        RecebeuDica (Err erro) ->
            ( falhou erro model, Cmd.none )

        TemaAlterado darkTheme ->
            ( { model | darkTheme = darkTheme }, Cmd.none )

        DescerPersonagens ->
            ( model, Task.attempt RecebeuPosicaoPersonagens (Browser.Dom.getViewportOf "bce-personagens-scroll") )

        RecebeuPosicaoPersonagens resultado ->
            case resultado of
                Ok viewport ->
                    let
                        limite =
                            max 0 (viewport.scene.height - viewport.viewport.height)

                        destino =
                            min limite (viewport.viewport.y + viewport.viewport.height * 0.75)
                    in
                    ( model
                    , Task.attempt (\_ -> RolagemConcluida)
                        (Browser.Dom.setViewportOf "bce-personagens-scroll" viewport.viewport.x destino)
                    )

                Err _ ->
                    ( model, Cmd.none )

        RolagemConcluida ->
            ( model, Cmd.none )


executar : Acao -> Model -> ( Model, Cmd Msg )
executar acao model =
    case acao of
        NovaFase dificuldade ->
            iniciar (Api.novaFase dificuldade (RecebeuFase dificuldade)) model

        Selecionar amigo ->
            duranteRodada model <|
                \partida ->
                    if List.member amigo (Bce.semAssento partida.fase partida.estado.sentados) then
                        ( { model | tela = PartidaAberta { partida | selecao = AmigoSelecionado amigo, erro = Nothing, aviso = Nothing } }
                        , Cmd.none
                        )

                    else
                        ( model, Cmd.none )

        AtivarCadeira posicao ->
            duranteRodada model (ativarCadeira posicao model)

        PedirDica ->
            duranteRodada model <|
                \partida ->
                    -- Com uma dica na tela, pedir de novo devolveria a mesma
                    -- jogada e só gastaria uma estrela.
                    case partida.dica of
                        Just _ ->
                            ( model, Cmd.none )

                        Nothing ->
                            iniciar (Api.dica partida.fase partida.estado.sentados RecebeuDica) model

        Resolver ->
            duranteRodada model <|
                \partida ->
                    iniciar (Api.resolver partida.fase partida.estado.sentados (RecebeuEstado Solucao)) model

        Recomecar ->
            case model.tela of
                PartidaAberta partida ->
                    iniciar (Api.estado partida.fase partida.fase.fixos (RecebeuEstado Reinicio)) model

                Inicio ->
                    ( model, Cmd.none )

                FalhaInicial _ ->
                    ( model, Cmd.none )


duranteRodada : Model -> (Partida -> ( Model, Cmd Msg )) -> ( Model, Cmd Msg )
duranteRodada model acao =
    case model.tela of
        PartidaAberta partida ->
            if partida.desfecho == Rodada Jogando then
                acao partida

            else
                ( model, Cmd.none )

        Inicio ->
            ( model, Cmd.none )

        FalhaInicial _ ->
            ( model, Cmd.none )


ativarCadeira : Posicao -> Model -> Partida -> ( Model, Cmd Msg )
ativarCadeira posicao model partida =
    let
        sentados =
            partida.estado.sentados
    in
    case Bce.ocupante sentados posicao of
        Just amigo ->
            case Bce.levantar partida.fase sentados amigo of
                Ok restantes ->
                    iniciar (Api.estado partida.fase restantes (RecebeuEstado (Levantada amigo partida.selecao))) model

                Err recusa ->
                    ( falhou (Bce.recusaParaTexto recusa) model, Cmd.none )

        Nothing ->
            case partida.selecao of
                NadaSelecionado ->
                    ( model, Cmd.none )

                AmigoSelecionado amigo ->
                    case Bce.sentar partida.fase sentados amigo posicao of
                        Ok _ ->
                            iniciar
                                (Api.jogada partida.fase sentados (Bce.Lugar amigo posicao) (RecebeuEstado (Jogada amigo posicao)))
                                model

                        Err recusa ->
                            ( falhou (Bce.recusaParaTexto recusa) model, Cmd.none )


iniciar : Cmd Msg -> Model -> ( Model, Cmd Msg )
iniciar comando model =
    let
        tela =
            case model.tela of
                PartidaAberta partida ->
                    PartidaAberta { partida | erro = Nothing, aviso = Nothing }

                Inicio ->
                    Inicio

                FalhaInicial _ ->
                    Inicio
    in
    ( { model | tela = tela, aguardando = True }, comando )


falhou : String -> Model -> Model
falhou erro model =
    let
        tela =
            case model.tela of
                PartidaAberta partida ->
                    PartidaAberta { partida | erro = Just erro }

                Inicio ->
                    FalhaInicial erro

                FalhaInicial _ ->
                    FalhaInicial erro
    in
    { model | tela = tela, aguardando = False }


mapPartida : (Partida -> Partida) -> Tela -> Tela
mapPartida transformar tela =
    case tela of
        PartidaAberta partida ->
            PartidaAberta (transformar partida)

        Inicio ->
            Inicio

        FalhaInicial erro ->
            FalhaInicial erro


aplicarEstado : Consulta -> Estado -> Tela -> Tela
aplicarEstado consulta estado tela =
    case consulta of
        FaseNova dificuldade fase ->
            PartidaAberta (novaPartida dificuldade fase estado)

        Reinicio ->
            mapPartida (\partida -> novaPartida partida.dificuldade partida.fase estado) tela

        Jogada _ posicao ->
            mapPartida
                (\partida ->
                    let
                        violacoesAnteriores =
                            Bce.conflitos partida.estado.status

                        novasViolacoes =
                            Bce.conflitos estado.status
                                |> List.filter (\amigo -> not (List.member amigo violacoesAnteriores))

                        partidaAtualizada =
                            aplicarJogada estado Nothing partida
                    in
                    { partidaAtualizada
                        | conflitoRecente =
                            if List.isEmpty novasViolacoes then
                                Nothing
                            else
                                Just posicao
                    }
                )
                tela

        Levantada levantado selecao ->
            mapPartida (aplicarJogada estado (avisoAoLevantar levantado selecao)) tela

        Solucao ->
            mapPartida
                (\partida ->
                    { partida | estado = estado, selecao = NadaSelecionado, desfecho = Resolvida, dica = Nothing, conflitoRecente = Nothing, erro = Nothing, aviso = Nothing }
                )
                tela


aplicarJogada : Estado -> Maybe String -> Partida -> Partida
aplicarJogada estado aviso partida =
    { partida
        | estado = estado
        , selecao = NadaSelecionado
        , desfecho = Rodada (rodada estado partida.dicasUsadas)
        , dica = Nothing
        , conflitoRecente = Nothing
        , erro = Nothing
        , aviso = aviso
    }


{-| Ativar a cadeira de alguém levanta essa pessoa mesmo com outro amigo
selecionado, e a seleção se perde. O aviso explica o que aconteceu.
-}
avisoAoLevantar : Amigo -> Selecao -> Maybe String
avisoAoLevantar levantado selecao =
    case selecao of
        NadaSelecionado ->
            Nothing

        AmigoSelecionado selecionado ->
            Just
                ("Você levantou "
                    ++ Bce.comArtigo levantado
                    ++ " e desfez a seleção d"
                    ++ Bce.comArtigo selecionado
                    ++ ". A cadeira estava ocupada; selecione um amigo de novo para sentá-lo."
                )


novaPartida : Dificuldade -> Fase -> Estado -> Partida
novaPartida dificuldade fase estado =
    { fase = fase
    , dificuldade = dificuldade
    , estado = estado
    , selecao = NadaSelecionado
    , desfecho = Rodada (rodada estado 0)
    , dica = Nothing
    , dicasUsadas = 0
    , conflitoRecente = Nothing
    , erro = Nothing
    , aviso = Nothing
    }


rodada : Estado -> Int -> Rodada
rodada estado dicas =
    if estado.venceu then
        Venceu (Bce.estrelasPorDicas dicas)

    else
        Jogando


view : Model -> Html Msg
view model =
    div [ classList [ ( "pixel-game", True ), ( "is-dark", model.darkTheme ) ] ]
        [ div [ class "game-shell" ]
            [ header [ class "game-header" ]
                [ img [ class "game-logo", src (sprite (if model.darkTheme then "logo-escuro" else "logo-claro")), alt "Mesa da BCE" ] []
                , label
                    [ class "theme-toggle"
                    , title (if model.darkTheme then "Ativar modo claro" else "Ativar modo noturno")
                    ]
                    [ input
                        [ type_ "checkbox"
                        , class "theme-controller"
                        , checked model.darkTheme
                        , attribute "aria-label" (if model.darkTheme then "Ativar modo claro" else "Ativar modo noturno")
                        , onCheck TemaAlterado
                        ]
                        []
                    , img
                        [ src (sprite (if model.darkTheme then "modo-claro" else "modo-noturno"))
                        , alt ""
                        , attribute "aria-hidden" "true"
                        ]
                        []
                    ]
                ]
            , main_ [ class "game-main", attribute "aria-busy" (boolText model.aguardando) ]
                [ viewTela model ]
            ]
        ]


sprite : String -> String
sprite name =
    "/sprites/" ++ name ++ ".svg"


amigoSprite : Amigo -> String
amigoSprite amigo =
    case amigo of
        Bce.Arthur -> "arthur"
        Bce.Bevi -> "bevi"
        Bce.Felipe -> "felipe"
        Bce.Gabriel -> "gabriel"
        Bce.Giovanna -> "giovanna"
        Bce.Joao -> "joao"
        Bce.Mayara -> "mayara"


classeGrid : Dificuldade -> String
classeGrid dificuldade =
    case dificuldade of
        Facil ->
            "desk-grid--facil"

        Medio ->
            "desk-grid--medio"

        Dificil ->
            "desk-grid--dificil"


viewDificuldade : Model -> Dificuldade -> Html Msg
viewDificuldade model dificuldade =
    let
        ativa =
            case model.tela of
                PartidaAberta partida -> partida.dificuldade == dificuldade
                _ -> False
    in
    button
        [ class "bce-nivel"
        , classList [ ( "bce-nivel--ativo", ativa ) ]
        , disabled model.aguardando
        , onClick (AcaoJogo (NovaFase dificuldade))
        ]
        [ text (Api.dificuldadeLabel dificuldade) ]


viewTela : Model -> Html Msg
viewTela model =
    case model.tela of
        Inicio ->
            p [ attribute "role" "status" ] [ text "Carregando fase…" ]

        FalhaInicial erro ->
            div [ class "game-error" ]
                [ viewErro erro
                , button [ onClick (AcaoJogo (NovaFase Facil)) ] [ text "Tentar novamente" ]
                ]

        PartidaAberta partida ->
            let
                jogavel =
                    not model.aguardando && partida.desfecho == Rodada Jogando
            in
            div [ class "game-content" ]
                [ section [ class "characters", attribute "aria-label" "Personagens e regras" ]
                    [ div [ class "characters-scroll", id "bce-personagens-scroll" ]
                        (List.map (viewAmigo jogavel partida) partida.fase.amigos)
                    , button
                        [ type_ "button"
                        , class "scroll-indicator"
                        , title "Ver mais personagens"
                        , attribute "aria-label" "Rolar a lista de personagens para baixo"
                        , onClick DescerPersonagens
                        ]
                        [ text "▼" ]
                    ]
                , section [ class "board-area", attribute "aria-label" "Tabuleiro do jogo" ]
                    [ div [ class "levels" ] (List.map (viewDificuldade model) [ Facil, Medio, Dificil ])
                    , div [ class "game-actions" ]
                        [ viewIconAcao "Dica" "dica" PedirDica (not jogavel || partida.dica /= Nothing)
                        , viewIconAcao "Resolver" "resolver" Resolver (not jogavel)
                        , viewIconAcao "Recomeçar" "recomecar" Recomecar model.aguardando
                        ]
                    , viewMensagens model.aguardando partida
                    , div [ class "classroom-layout" ]
                        [ div
                            [ class ("desk-grid " ++ classeGrid partida.dificuldade)
                            , style "display" "flex"
                            , style "flex-direction" "column"
                            ]
                            (List.range 0 (partida.fase.linhas - 1)
                                |> List.map (viewLinhaMesas jogavel partida)
                            )
                        ]
                    ]
                ]


viewIconAcao : String -> String -> Acao -> Bool -> Html Msg
viewIconAcao rotulo icone acao bloqueada =
    button
        [ type_ "button", class "icon-action", title rotulo, attribute "aria-label" rotulo
        , disabled bloqueada, onClick (AcaoJogo acao)
        ]
        [ img [ src (sprite icone), alt rotulo ] [] ]


viewMensagens : Bool -> Partida -> Html Msg
viewMensagens aguardando partida =
    div [ class "game-messages", attribute "aria-live" "polite" ]
        [ case partida.erro of
            Just erro -> viewErro erro
            Nothing -> text ""
        , case partida.aviso of
            Just aviso -> p [ class "message message--info" ] [ text aviso ]
            Nothing -> text ""
        , viewConflitos partida
        , p [ class "game-status", attribute "role" "status" ]
            [ text
                (if aguardando then
                    "O Prolog está pensando…"
                 else
                    case partida.desfecho of
                        Rodada Jogando ->
                            case partida.dica of
                                Just dica -> Bce.explicarDica dica
                                Nothing -> ""
                        Rodada (Venceu estrelas) -> "Você venceu! " ++ textoEstrelas estrelas
                        Resolvida -> "Resolvido com ajuda"
                )
            ]
        ]


{-| O backend avalia as manias: somente status Violada é um conflito
confirmado. Pendente não deve receber destaque vermelho, pois ainda
faltam amigos para avaliar a regra.
-}
viewConflitos : Partida -> Html Msg
viewConflitos partida =
    let
        violados =
            Bce.conflitos partida.estado.status

        regrasVioladas =
            partida.fase.manias
                |> List.filter (\regra -> List.member regra.dono violados)
    in
    if List.isEmpty regrasVioladas then
        text ""

    else
        div [ class "game-conflicts", attribute "role" "alert" ]
            (p [ class "game-conflicts-title" ]
                [ text "✕ Há uma regra que não está sendo respeitada:" ]
                :: List.map
                    (\regra ->
                        p [ class "game-conflicts-reason" ]
                            [ text (Bce.descreverMania regra) ]
                    )
                    regrasVioladas
            )


viewErro : String -> Html Msg
viewErro erro =
    p [ class "message message--error", attribute "role" "alert" ] [ text erro ]


viewAmigo : Bool -> Partida -> Amigo -> Html Msg
viewAmigo jogavel partida amigo =
    let
        sentado =
            not (List.member amigo (Bce.semAssento partida.fase partida.estado.sentados))
        status =
            Bce.statusDe partida.estado.status amigo
        selecionado =
            partida.selecao == AmigoSelecionado amigo
        manias =
            partida.fase.manias
                |> List.filter (\regra -> regra.dono == amigo)
                |> List.map (\regra -> p [ class "character-rule" ] [ text (Bce.descreverMania regra) ])
        conteudo =
            [ img [ class "character-image", src (sprite (amigoSprite amigo)), alt (Bce.nomeDoAmigo amigo) ] []
            , span [ class "character-name" ] [ text (Bce.nomeDoAmigo amigo) ]
            ] ++ manias
        classes =
            [ class "character-card"
            , classList
                [ ( "bce-selecionado", selecionado )
                , ( "bce-conflito", status == Violada )
                , ( "bce-destaque", Maybe.map .amigo partida.dica == Just amigo )
                , ( "is-seated", sentado )
                ]
            ]
    in
    if sentado then
        div (classes ++ [ title "Personagem sentado" ]) conteudo
    else
        button
            (classes ++ [ type_ "button", disabled (not jogavel), attribute "aria-pressed" (boolText selecionado), onClick (AcaoJogo (Selecionar amigo)) ])
            conteudo


{-| Renderizar cada linha explicitamente impede que as cadeiras fiquem
empilhadas em uma única coluna, inclusive se outra regra CSS modificar
o container. As coordenadas seguem a matriz fornecida pelo backend.
-}
viewLinhaMesas : Bool -> Partida -> Int -> Html Msg
viewLinhaMesas jogavel partida linha =
    div
        [ class "desk-row"
        , style "display" "flex"
        , style "flex-direction" "row"
        , style "flex-wrap" "nowrap"
        ]
        ((List.range 0 (partida.fase.colunas - 1)
            |> List.map
                (\coluna ->
                    viewCadeira jogavel partida { linha = linha, coluna = coluna }
                )
         )
            ++ (if linha == 0 then
                    [ img
                        [ class "door-marker"
                        , src (sprite "marcador-porta")
                        , alt ""
                        , attribute "aria-hidden" "true"
                        ]
                        []
                    ]

                else
                    []
               )
        )


viewCadeira : Bool -> Partida -> Posicao -> Html Msg
viewCadeira jogavel partida posicao =
    let
        fixo =
            List.any (\lugar -> lugar.posicao == posicao) partida.fase.fixos
        ocupante =
            Bce.ocupante partida.estado.sentados posicao
        objeto =
            Bce.objetoEm partida.fase posicao
        spriteMesa =
            case ocupante of
                Just amigo ->
                    case objeto of
                        Just Tomada ->
                            amigoSprite amigo ++ "-mesa-tomada"

                        _ ->
                            amigoSprite amigo ++ "-mesa"

                Nothing ->
                    case objeto of
                        Just Tomada -> "tomada"
                        Just Porta -> "mesa"
                        _ -> "mesa"
        conteudo =
            case ocupante of
                Just amigo -> Bce.nomeDoAmigo amigo ++ (if fixo then " (fixo)" else "")
                Nothing -> "Cadeira livre"
        coordenada =
            "Linha " ++ String.fromInt (posicao.linha + 1) ++ ", coluna " ++ String.fromInt (posicao.coluna + 1)
        rotulo =
            String.join ", " [ coordenada, conteudo ]

        regraViolada =
            case ocupante of
                Just amigo ->
                    Bce.statusDe partida.estado.status amigo == Violada

                Nothing ->
                    False

        destaqueErro =
            regraViolada || (ocupante /= Nothing && partida.conflitoRecente == Just posicao)
    in
    button
        [ type_ "button", class "desk"
        , classList
            [ ( "bce-fixo", fixo )
            , ( "bce-destaque", Maybe.map .posicao partida.dica == Just posicao )
            , ( "bce-conflito", destaqueErro )
            , ( "desk-occupied", ocupante /= Nothing )
            ]
        , disabled (fixo || not jogavel || (ocupante == Nothing && partida.selecao == NadaSelecionado))
        , attribute "aria-label" rotulo
        , title rotulo
        , onClick (AcaoJogo (AtivarCadeira posicao))
        ]
        [ img [ src (sprite spriteMesa), alt "" ] [] ]


textoObjeto : Objeto -> String
textoObjeto objeto =
    case objeto of
        Janela ->
            "Janela"

        Tomada ->
            "Tomada"

        Porta ->
            "Porta"

        Estante ->
            "Estante"


textoStatus : StatusMania -> String
textoStatus status =
    case status of
        Respeitada ->
            "Respeitada"

        Violada ->
            "Violada"

        Pendente ->
            "Pendente"


textoEstrelas : Estrelas -> String
textoEstrelas estrelas =
    case estrelas of
        TresEstrelas ->
            "3 estrelas"

        DuasEstrelas ->
            "2 estrelas"

        UmaEstrela ->
            "1 estrela"


boolText : Bool -> String
boolText valor =
    if valor then
        "true"

    else
        "false"
