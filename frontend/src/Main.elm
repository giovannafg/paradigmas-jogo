module Main exposing (Acao(..), Consulta(..), Desfecho(..), Msg(..), Tela(..), init, main, update)

import Api exposing (Dificuldade(..), Estado)
import Bce exposing (Amigo, Dica, Estrelas(..), Fase, Objeto(..), Posicao, Rodada(..), Selecao(..), StatusMania(..))
import Browser
import Html exposing (Html, button, div, h1, h2, header, input, label, main_, p, section, span, text)
import Html.Attributes exposing (attribute, checked, class, classList, disabled, id, style, type_, value)
import Html.Events exposing (onCheck, onClick)


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
    , erro : Maybe String
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
    | Jogada
    | Reinicio
    | Solucao


type Msg
    = AcaoJogo Acao
    | RecebeuFase Dificuldade (Result String Fase)
    | RecebeuEstado Consulta (Result String Estado)
    | RecebeuDica (Result String Dica)
    | TemaAlterado Bool


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


executar : Acao -> Model -> ( Model, Cmd Msg )
executar acao model =
    case acao of
        NovaFase dificuldade ->
            iniciar (Api.novaFase dificuldade (RecebeuFase dificuldade)) model

        Selecionar amigo ->
            duranteRodada model <|
                \partida ->
                    if List.member amigo (Bce.semAssento partida.fase partida.estado.sentados) then
                        ( { model | tela = PartidaAberta { partida | selecao = AmigoSelecionado amigo, erro = Nothing } }
                        , Cmd.none
                        )

                    else
                        ( model, Cmd.none )

        AtivarCadeira posicao ->
            duranteRodada model (ativarCadeira posicao model)

        PedirDica ->
            duranteRodada model <|
                \partida ->
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
                    iniciar (Api.estado partida.fase restantes (RecebeuEstado Jogada)) model

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
                                (Api.jogada partida.fase sentados (Bce.Lugar amigo posicao) (RecebeuEstado Jogada))
                                model

                        Err recusa ->
                            ( falhou (Bce.recusaParaTexto recusa) model, Cmd.none )


iniciar : Cmd Msg -> Model -> ( Model, Cmd Msg )
iniciar comando model =
    let
        tela =
            case model.tela of
                PartidaAberta partida ->
                    PartidaAberta { partida | erro = Nothing }

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

        Jogada ->
            mapPartida
                (\partida ->
                    { partida
                        | estado = estado
                        , selecao = NadaSelecionado
                        , desfecho = Rodada (rodada estado partida.dicasUsadas)
                        , dica = Nothing
                        , erro = Nothing
                    }
                )
                tela

        Solucao ->
            mapPartida
                (\partida ->
                    { partida | estado = estado, selecao = NadaSelecionado, desfecho = Resolvida, dica = Nothing, erro = Nothing }
                )
                tela


novaPartida : Dificuldade -> Fase -> Estado -> Partida
novaPartida dificuldade fase estado =
    { fase = fase
    , dificuldade = dificuldade
    , estado = estado
    , selecao = NadaSelecionado
    , desfecho = Rodada (rodada estado 0)
    , dica = Nothing
    , dicasUsadas = 0
    , erro = Nothing
    }


rodada : Estado -> Int -> Rodada
rodada estado dicas =
    if estado.venceu then
        Venceu (Bce.estrelasPorDicas dicas)

    else
        Jogando


view : Model -> Html Msg
view model =
    div [ class "app" ]
        [ header [ class "app-header" ]
            [ div [ class "app-container app-header-content" ]
                [ h1 [ class "app-title" ] [ text "Mesa da BCE" ]
                , label [ class "theme-toggle", attribute "aria-label" "Alternar tema escuro" ]
                    [ input [ type_ "checkbox", class "theme-controller", value "dark", checked model.darkTheme, onCheck TemaAlterado ] []
                    , span [ class "swap-off", attribute "aria-hidden" "true" ] [ text "☀" ]
                    , span [ class "swap-on", attribute "aria-hidden" "true" ] [ text "☾" ]
                    ]
                ]
            ]
        , main_ [ class "app-main" ]
            [ div [ class "app-container bce-layout", attribute "aria-busy" (boolText model.aguardando) ]
                [ section [ class "bce-toolbar", attribute "aria-label" "Nova fase" ]
                    [ h2 [] [ text "Nova fase" ]
                    , div [ class "difficulty-picker" ]
                        (List.map (viewDificuldade model) [ Facil, Medio, Dificil ])
                    ]
                , viewTela model
                ]
            ]
        ]


viewDificuldade : Model -> Dificuldade -> Html Msg
viewDificuldade model dificuldade =
    let
        ativa =
            case model.tela of
                PartidaAberta partida ->
                    partida.dificuldade == dificuldade

                Inicio ->
                    False

                FalhaInicial _ ->
                    False
    in
    button
        [ class "difficulty-option"
        , classList [ ( "difficulty-option--active", ativa ) ]
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
            viewErro erro

        PartidaAberta partida ->
            let
                jogavel =
                    not model.aguardando && partida.desfecho == Rodada Jogando
            in
            div [ class "bce-layout" ]
                [ div [ class "bce-acoes" ]
                    [ viewAcao "Dica" PedirDica (not jogavel)
                    , viewAcao "Resolver" Resolver (not jogavel)
                    , viewAcao "Recomeçar" Recomecar model.aguardando
                    ]
                , viewMensagens model.aguardando partida
                , div [ class "bce-partida" ]
                    [ section [ attribute "aria-labelledby" "amigos-titulo" ]
                        [ h2 [ id "amigos-titulo" ] [ text "Amigos" ]
                        , p [ class "bce-instrucao" ] [ text "Selecione um amigo e escolha uma cadeira livre. Para levantar alguém, ative a cadeira dele." ]
                        , div [ class "bce-amigos" ]
                            (List.map (viewAmigo jogavel partida) partida.fase.amigos)
                        ]
                    , section [ attribute "aria-labelledby" "mesa-titulo" ]
                        [ h2 [ id "mesa-titulo" ] [ text "Mesa" ]
                        , div
                            [ class "bce-mesa"
                            , style "--bce-colunas" (String.fromInt partida.fase.colunas)
                            ]
                            (List.map (viewCadeira jogavel partida) (Bce.posicoes partida.fase))
                        ]
                    ]
                ]


viewAcao : String -> Acao -> Bool -> Html Msg
viewAcao rotulo acao bloqueada =
    button [ class "btn", disabled bloqueada, onClick (AcaoJogo acao) ] [ text rotulo ]


viewMensagens : Bool -> Partida -> Html Msg
viewMensagens aguardando partida =
    div []
        [ case partida.erro of
            Just erro ->
                viewErro erro

            Nothing ->
                text ""
        , p [ attribute "role" "status" ]
            [ text
                (if aguardando then
                    "O Prolog está pensando…"

                 else
                    case partida.desfecho of
                        Rodada Jogando ->
                            case partida.dica of
                                Just dica ->
                                    Bce.explicarDica dica

                                Nothing ->
                                    ""

                        Rodada (Venceu estrelas) ->
                            "Você venceu! " ++ textoEstrelas estrelas

                        Resolvida ->
                            "Resolvido com ajuda"
                )
            ]
        ]


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
                |> List.map (Bce.descreverMania >> text >> List.singleton >> span [ class "bce-mania" ])

        conteudo =
            [ span [ class "bce-nome" ] [ text (Bce.nomeDoAmigo amigo) ]
            , span [] [ text (textoStatus status) ]
            ]
                ++ manias

        classes =
            [ class "bce-card"
            , classList
                [ ( "bce-selecionado", selecionado )
                , ( "bce-conflito", status == Violada )
                , ( "bce-destaque", Maybe.map .amigo partida.dica == Just amigo )
                ]
            ]
    in
    if sentado then
        div classes (conteudo ++ [ span [] [ text "Sentado" ] ])

    else
        button
            (classes
                ++ [ type_ "button"
                   , disabled (not jogavel)
                   , attribute "aria-pressed" (boolText selecionado)
                   , onClick (AcaoJogo (Selecionar amigo))
                   ]
            )
            conteudo


viewCadeira : Bool -> Partida -> Posicao -> Html Msg
viewCadeira jogavel partida posicao =
    let
        fixo =
            List.any (\lugar -> lugar.posicao == posicao) partida.fase.fixos

        ocupante =
            Bce.ocupante partida.estado.sentados posicao

        conteudo =
            case ocupante of
                Just amigo ->
                    if fixo then
                        Bce.nomeDoAmigo amigo ++ " · fixo"

                    else
                        Bce.nomeDoAmigo amigo

                Nothing ->
                    "Livre"

        objeto =
            Bce.objetoEm partida.fase posicao
                |> Maybe.map textoObjeto
                |> Maybe.withDefault ""

        coordenada =
            "Linha "
                ++ String.fromInt (posicao.linha + 1)
                ++ ", coluna "
                ++ String.fromInt (posicao.coluna + 1)

        rotulo =
            String.join ", " (List.filter (not << String.isEmpty) [ coordenada, conteudo, objeto ])
    in
    button
        [ type_ "button"
        , class "bce-cadeira"
        , classList
            [ ( "bce-fixo", fixo )
            , ( "bce-destaque", Maybe.map .posicao partida.dica == Just posicao )
            ]
        , disabled (fixo || not jogavel || (ocupante == Nothing && partida.selecao == NadaSelecionado))
        , attribute "aria-label" rotulo
        , onClick (AcaoJogo (AtivarCadeira posicao))
        ]
        [ span [] [ text conteudo ]
        , span [] [ text objeto ]
        ]


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
