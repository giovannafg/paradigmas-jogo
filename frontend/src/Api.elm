module Api exposing
    ( Difficulty(..)
    , Estado
    , Hint
    , difficultyLabel
    , generate
    , hint
    , solve
    )

{-| Comunicação com o backend (FastAPI + Prolog).

Em Elm, uma requisição HTTP não "acontece" quando chamamos uma função. As
funções deste módulo devolvem um `Cmd msg`: uma DESCRIÇÃO do efeito que
queremos. Quem executa o efeito é o runtime do Elm; quando a resposta chega,
ele chama nosso `update` com a mensagem que indicamos (por exemplo,
`GotPuzzle resultado`). É assim que o Elm mantém todas as funções puras.

As URLs começam com `/api/...`. Em desenvolvimento, o Vite repassa essas
requisições para o backend em <http://localhost:8000> (veja vite.config.js).

-}

import Bce exposing (Amigo, Dica, Fase, Lugar, Objeto, Posicao, Regra, StatusMania(..))
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Sudoku exposing (Board)


type Difficulty
    = Easy
    | Medium
    | Hard


difficultyLabel : Difficulty -> String
difficultyLabel difficulty =
    case difficulty of
        Easy ->
            "Fácil"

        Medium ->
            "Médio"

        Hard ->
            "Difícil"


{-| Nome usado pela API (e pelo Prolog: são os átomos easy/medium/hard).
-}
difficultyToString : Difficulty -> String
difficultyToString difficulty =
    case difficulty of
        Easy ->
            "easy"

        Medium ->
            "medium"

        Hard ->
            "hard"


{-| Um _record_ (registro): um conjunto de campos com nome. O `type alias`
também cria automaticamente uma função construtora `Hint : Int -> Int -> Int
-> Hint`, que usamos no decoder abaixo.
-}
type alias Hint =
    { row : Int
    , col : Int
    , value : Int
    }



-- REQUISIÇÕES
--
-- Todas recebem uma função `toMsg` que diz como embrulhar o resultado numa
-- mensagem. `Result String a` é: ou `Ok valor`, ou `Err mensagemDeErro`.


generate : Difficulty -> (Result String Board -> msg) -> Cmd msg
generate difficulty toMsg =
    Http.post
        { url = "/api/generate"
        , body =
            Http.jsonBody
                (Encode.object [ ( "difficulty", Encode.string (difficultyToString difficulty) ) ])
        , expect = expectJson toMsg boardDecoder
        }


solve : Board -> (Result String Board -> msg) -> Cmd msg
solve board toMsg =
    Http.post
        { url = "/api/solve"
        , body = Http.jsonBody (encodeBoard board)
        , expect = expectJson toMsg boardDecoder
        }


hint : Board -> (Result String Hint -> msg) -> Cmd msg
hint board toMsg =
    Http.post
        { url = "/api/hint"
        , body = Http.jsonBody (encodeBoard board)
        , expect = expectJson toMsg hintDecoder
        }



-- JSON
--
-- Elm não converte JSON em valores "magicamente". Escrevemos DECODERS, que
-- descrevem a forma esperada do JSON. Se o JSON vier diferente, a decodificação
-- falha com uma mensagem de erro, em vez de gerar um valor inválido.


{-| Envia `{"board": [[5,3,0,...], ...]}`.
-}
encodeBoard : Board -> Encode.Value
encodeBoard board =
    Encode.object
        [ ( "board", Encode.list (Encode.list Encode.int) (Sudoku.toLists board) ) ]


{-| Lê `{"board": [[...], ...]}`. Decoders se combinam como peças de Lego:
`Decode.list (Decode.list Decode.int)` é "uma lista de listas de inteiros".
-}
boardDecoder : Decoder Board
boardDecoder =
    Decode.field "board" (Decode.list (Decode.list Decode.int))
        |> Decode.map Sudoku.fromLists


{-| `Decode.map3` junta três decoders e passa os três resultados para a
função `Hint` (o construtor do record).
-}
hintDecoder : Decoder Hint
hintDecoder =
    Decode.map3 Hint
        (Decode.field "row" Decode.int)
        (Decode.field "col" Decode.int)
        (Decode.field "value" Decode.int)



-- MESA DA BCE: JSON PARA OS TIPOS DO Bce.elm
--
-- O formato do JSON está em docs/API.md. Cada decoder FALHA quando recebe um
-- valor que não existe no jogo (amigo, objeto, mania ou status desconhecido),
-- em vez de aceitar um dado inválido: assim um erro no servidor aparece logo
-- aqui, e não lá na tela.


{-| O que muda a cada jogada, como as rotas de estado, jogada e resolver
devolvem. `sentados` inclui os fixos.
-}
type alias Estado =
    { sentados : List Lugar
    , status : List ( Amigo, StatusMania )
    , venceu : Bool
    }


{-| `{"mesa": {...}, "amigos": [...], "fixos": [...], "manias": [...]}`.
O JSON aninha o tamanho da mesa em `mesa`; `Decode.at` lê o caminho inteiro.
-}
faseDecoder : Decoder Fase
faseDecoder =
    Decode.map6 Fase
        (Decode.at [ "mesa", "linhas" ] Decode.int)
        (Decode.at [ "mesa", "colunas" ] Decode.int)
        (Decode.at [ "mesa", "objetos" ] (Decode.list objetoNaMesaDecoder))
        (Decode.field "amigos" (Decode.list amigoDecoder))
        (Decode.field "fixos" (Decode.list lugarDecoder))
        (Decode.field "manias" (Decode.list regraDecoder))


estadoDecoder : Decoder Estado
estadoDecoder =
    Decode.map3 Estado
        (Decode.field "sentados" (Decode.list lugarDecoder))
        (Decode.field "status" (Decode.list statusDoAmigoDecoder))
        (Decode.field "venceu" Decode.bool)


{-| `motivo` é `null` quando a cadeira sobra só por eliminação;
`Decode.nullable` transforma isso em `Nothing`.
-}
dicaDecoder : Decoder Dica
dicaDecoder =
    Decode.map3 Dica
        (Decode.field "amigo" amigoDecoder)
        posicaoDecoder
        (Decode.field "motivo" (Decode.nullable regraDecoder))


{-| Linha e coluna vêm soltas no mesmo objeto do amigo ou do objeto, então
este decoder lê os dois campos do objeto atual.
-}
posicaoDecoder : Decoder Posicao
posicaoDecoder =
    Decode.map2 Posicao
        (Decode.field "linha" Decode.int)
        (Decode.field "coluna" Decode.int)


lugarDecoder : Decoder Lugar
lugarDecoder =
    Decode.map2 Lugar
        (Decode.field "amigo" amigoDecoder)
        posicaoDecoder


objetoNaMesaDecoder : Decoder ( Objeto, Posicao )
objetoNaMesaDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "objeto" objetoDecoder)
        posicaoDecoder


{-| Primeiro lê os três campos; depois `Decode.andThen` olha o resultado e
decide se a mania existe. `Bce.maniaDeTexto` é quem sabe a resposta.
-}
regraDecoder : Decoder Regra
regraDecoder =
    Decode.map3 (\dono tipo alvo -> ( dono, tipo, alvo ))
        (Decode.field "amigo" amigoDecoder)
        (Decode.field "tipo" Decode.string)
        (Decode.field "alvo" alvoDecoder)
        |> Decode.andThen
            (\( dono, tipo, alvo ) ->
                Bce.maniaDeTexto tipo alvo
                    |> Result.map (Regra dono)
                    |> deResult
            )


{-| O `alvo` chega como `null`, como um texto (`"porta"`) ou como uma lista
(`["arthur", "joao"]`). `Decode.oneOf` tenta cada forma e as três viram a
lista de textos que `Bce.maniaDeTexto` espera.
-}
alvoDecoder : Decoder (List String)
alvoDecoder =
    Decode.oneOf
        [ Decode.null []
        , Decode.map List.singleton Decode.string
        , Decode.list Decode.string
        ]


statusDoAmigoDecoder : Decoder ( Amigo, StatusMania )
statusDoAmigoDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "amigo" amigoDecoder)
        (Decode.field "status" statusDecoder)


statusDecoder : Decoder StatusMania
statusDecoder =
    Decode.string
        |> Decode.andThen
            (\texto ->
                case texto of
                    "ok" ->
                        Decode.succeed Respeitada

                    "violada" ->
                        Decode.succeed Violada

                    "pendente" ->
                        Decode.succeed Pendente

                    _ ->
                        Decode.fail ("Status desconhecido: " ++ texto)
            )


amigoDecoder : Decoder Amigo
amigoDecoder =
    Decode.string
        |> Decode.andThen
            (\texto ->
                Bce.amigoDeTexto texto
                    |> Result.fromMaybe ("Amigo desconhecido: " ++ texto)
                    |> deResult
            )


objetoDecoder : Decoder Objeto
objetoDecoder =
    Decode.string
        |> Decode.andThen
            (\texto ->
                Bce.objetoDeTexto texto
                    |> Result.fromMaybe ("Objeto desconhecido: " ++ texto)
                    |> deResult
            )


{-| Transforma um `Result` num decoder: `Ok` vira sucesso e `Err` faz a
decodificação inteira falhar com aquela mensagem.
-}
deResult : Result String a -> Decoder a
deResult resultado =
    case resultado of
        Ok valor ->
            Decode.succeed valor

        Err erro ->
            Decode.fail erro



-- MESA DA BCE: TIPOS PARA JSON


{-| O corpo comum das rotas de estado, dica e resolver:
`{"fase": ..., "sentados": [...]}`.
-}
encodePedido : Fase -> List Lugar -> List ( String, Encode.Value )
encodePedido fase sentados =
    [ ( "fase", encodeFase fase )
    , ( "sentados", Encode.list encodeLugar sentados )
    ]


{-| As manias ficam de fora de propósito: o servidor ignora as que receber,
porque quem decide as manias é o Prolog (docs/API.md).
-}
encodeFase : Fase -> Encode.Value
encodeFase fase =
    Encode.object
        [ ( "mesa"
          , Encode.object
                [ ( "linhas", Encode.int fase.linhas )
                , ( "colunas", Encode.int fase.colunas )
                , ( "objetos", Encode.list encodeObjetoNaMesa fase.objetos )
                ]
          )
        , ( "amigos", Encode.list encodeAmigo fase.amigos )
        , ( "fixos", Encode.list encodeLugar fase.fixos )
        ]


encodeLugar : Lugar -> Encode.Value
encodeLugar lugar =
    Encode.object (( "amigo", encodeAmigo lugar.amigo ) :: encodePosicao lugar.posicao)


encodeObjetoNaMesa : ( Objeto, Posicao ) -> Encode.Value
encodeObjetoNaMesa ( objeto, posicao ) =
    Encode.object (( "objeto", Encode.string (Bce.objetoParaTexto objeto) ) :: encodePosicao posicao)


{-| Devolve só os campos, e não um objeto, porque linha e coluna vão
soltas dentro do objeto do amigo ou do objeto da mesa.
-}
encodePosicao : Posicao -> List ( String, Encode.Value )
encodePosicao posicao =
    [ ( "linha", Encode.int posicao.linha )
    , ( "coluna", Encode.int posicao.coluna )
    ]


encodeAmigo : Amigo -> Encode.Value
encodeAmigo amigo =
    Encode.string (Bce.amigoParaTexto amigo)



-- TRATAMENTO DE ERROS
--
-- `Http.expectJson` já existe, mas quando o servidor responde com erro (ex.:
-- 422) ele descarta o corpo da resposta. Nosso backend manda uma mensagem útil
-- em `{"detail": "..."}`, então escrevemos nossa própria versão, que olha o
-- corpo e devolve sempre um `Result String a` com mensagens em português.


expectJson : (Result String a -> msg) -> Decoder a -> Http.Expect msg
expectJson toMsg decoder =
    Http.expectStringResponse toMsg <|
        \response ->
            case response of
                Http.GoodStatus_ _ body ->
                    Decode.decodeString decoder body
                        |> Result.mapError (\_ -> "Resposta inesperada do servidor.")

                Http.BadStatus_ metadata body ->
                    Err (errorDetail metadata.statusCode body)

                Http.BadUrl_ url ->
                    Err ("URL inválida: " ++ url)

                Http.Timeout_ ->
                    Err "O servidor demorou demais para responder."

                Http.NetworkError_ ->
                    Err "Não foi possível falar com o servidor. O backend está rodando?"


{-| Tenta extrair o campo `detail` (quando ele é uma string). Se não der,
monta uma mensagem genérica com o código HTTP.
-}
errorDetail : Int -> String -> String
errorDetail status body =
    case Decode.decodeString (Decode.field "detail" Decode.string) body of
        Ok detail ->
            detail

        Err _ ->
            "Erro no servidor (código " ++ String.fromInt status ++ ")."
