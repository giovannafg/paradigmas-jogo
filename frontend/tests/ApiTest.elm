module ApiTest exposing (suite)

{-| Testes do JSON da Mesa da BCE (elm-test).

Conferem que os decoders transformam o JSON do backend (docs/API.md) nos
tipos do `Bce.elm` e que FALHAM com dados que não existem no jogo. Os JSON
de exemplo seguem as respostas do backend para a fase de exemplo do
REGRAS.md.

Rodar: `npx elm-test` (na pasta frontend) ou `make test-frontend` (na raiz).

-}

import Api
import Bce exposing (Amigo(..), Mania(..), Objeto(..), StatusMania(..))
import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Api"
        [ describe "faseDecoder"
            [ test "lê a fase de exemplo" <|
                \_ ->
                    Decode.decodeString Api.faseDecoder faseJson
                        |> Expect.equal (Ok fase)
            , test "falha com objeto desconhecido" <|
                \_ ->
                    faseJson
                        |> String.replace "\"tomada\"" "\"sofa\""
                        |> Decode.decodeString Api.faseDecoder
                        |> Expect.err
            , test "falha com amigo desconhecido" <|
                \_ ->
                    faseJson
                        |> String.replace "\"arthur\"" "\"xuxa\""
                        |> Decode.decodeString Api.faseDecoder
                        |> Expect.err
            , test "falha com mania desconhecida" <|
                \_ ->
                    faseJson
                        |> String.replace "\"sem_vizinhos\"" "\"voar\""
                        |> Decode.decodeString Api.faseDecoder
                        |> Expect.err
            ]
        , describe "estadoDecoder"
            [ test "lê o estado com os status das manias" <|
                \_ ->
                    Decode.decodeString Api.estadoDecoder estadoJson
                        |> Expect.equal
                            (Ok
                                { sentados = [ bevi, lugar Mayara 0 1 ]
                                , status =
                                    [ ( Arthur, Pendente )
                                    , ( Joao, Pendente )
                                    , ( Mayara, Violada )
                                    , ( Bevi, Respeitada )
                                    ]
                                , venceu = False
                                }
                            )
            , test "falha com status desconhecido" <|
                \_ ->
                    estadoJson
                        |> String.replace "\"violada\"" "\"talvez\""
                        |> Decode.decodeString Api.estadoDecoder
                        |> Expect.err
            ]
        , describe "dicaDecoder"
            [ test "lê a dica com o motivo" <|
                \_ ->
                    Decode.decodeString Api.dicaDecoder
                        """{"amigo": "joao", "linha": 0, "coluna": 2,
                            "motivo": {"amigo": "joao", "tipo": "na_cadeira_de", "alvo": "tomada"}}"""
                        |> Expect.equal
                            (Ok
                                { amigo = Joao
                                , posicao = { linha = 0, coluna = 2 }
                                , motivo = Just { dono = Joao, mania = NaCadeiraDe Tomada }
                                }
                            )
            , test "motivo null vira Nothing" <|
                \_ ->
                    Decode.decodeString Api.dicaDecoder
                        """{"amigo": "joao", "linha": 0, "coluna": 1, "motivo": null}"""
                        |> Result.map .motivo
                        |> Expect.equal (Ok Nothing)
            , test "alvo em lista vira DeFrentePara" <|
                \_ ->
                    Decode.decodeString Api.dicaDecoder
                        """{"amigo": "felipe", "linha": 1, "coluna": 0,
                            "motivo": {"amigo": "felipe", "tipo": "de_frente_para_algum", "alvo": ["arthur", "joao"]}}"""
                        |> Result.map .motivo
                        |> Expect.equal (Ok (Just { dono = Felipe, mania = DeFrentePara [ Arthur, Joao ] }))
            , test "falha quando o alvo não combina com a mania" <|
                \_ ->
                    Decode.decodeString Api.dicaDecoder
                        """{"amigo": "joao", "linha": 0, "coluna": 1,
                            "motivo": {"amigo": "joao", "tipo": "perto_de", "alvo": "porta"}}"""
                        |> Expect.err
            ]
        , describe "encodePedido"
            [ test "monta o corpo das rotas sem as manias" <|
                \_ ->
                    Encode.encode 0 (Encode.object (Api.encodePedido fase [ bevi ]))
                        |> Expect.equal
                            ("{\"fase\":{\"mesa\":{\"linhas\":2,\"colunas\":3,\"objetos\":"
                                ++ "[{\"objeto\":\"porta\",\"linha\":0,\"coluna\":0},"
                                ++ "{\"objeto\":\"tomada\",\"linha\":0,\"coluna\":2}]},"
                                ++ "\"amigos\":[\"arthur\",\"joao\",\"mayara\",\"bevi\"],"
                                ++ "\"fixos\":[{\"amigo\":\"bevi\",\"linha\":1,\"coluna\":1}]},"
                                ++ "\"sentados\":[{\"amigo\":\"bevi\",\"linha\":1,\"coluna\":1}]}"
                            )
            ]
        , describe "errorDetail"
            [ test "usa a mensagem do backend" <|
                \_ ->
                    Api.errorDetail 422 """{"detail": "Todo mundo já está sentado."}"""
                        |> Expect.equal "Todo mundo já está sentado."
            , test "detail em lista vira uma frase" <|
                \_ ->
                    Api.errorDetail 422 """{"detail": [{"loc": ["body", "linha"], "msg": "Input should be >= 0"}]}"""
                        |> Expect.equal "O jogo mandou dados fora do formato para o servidor."
            , test "resposta sem JSON mostra o código" <|
                \_ ->
                    Api.errorDetail 500 "Internal Server Error"
                        |> Expect.equal "Erro no servidor (código 500)."
            ]
        ]



-- DADOS DE EXEMPLO


faseJson : String
faseJson =
    """{"mesa": {"linhas": 2, "colunas": 3, "objetos": [
            {"objeto": "porta", "linha": 0, "coluna": 0},
            {"objeto": "tomada", "linha": 0, "coluna": 2}]},
        "amigos": ["arthur", "joao", "mayara", "bevi"],
        "fixos": [{"amigo": "bevi", "linha": 1, "coluna": 1}],
        "manias": [
            {"amigo": "arthur", "tipo": "perto_de_objeto", "alvo": "porta"},
            {"amigo": "joao", "tipo": "na_cadeira_de", "alvo": "tomada"},
            {"amigo": "mayara", "tipo": "longe_de", "alvo": "joao"},
            {"amigo": "bevi", "tipo": "sem_vizinhos", "alvo": null}]}"""


estadoJson : String
estadoJson =
    """{"sentados": [{"amigo": "bevi", "linha": 1, "coluna": 1},
                     {"amigo": "mayara", "linha": 0, "coluna": 1}],
        "status": [{"amigo": "arthur", "status": "pendente"},
                   {"amigo": "joao", "status": "pendente"},
                   {"amigo": "mayara", "status": "violada"},
                   {"amigo": "bevi", "status": "ok"}],
        "venceu": false}"""


fase : Bce.Fase
fase =
    { linhas = 2
    , colunas = 3
    , objetos =
        [ ( Porta, { linha = 0, coluna = 0 } )
        , ( Tomada, { linha = 0, coluna = 2 } )
        ]
    , amigos = [ Arthur, Joao, Mayara, Bevi ]
    , fixos = [ bevi ]
    , manias =
        [ { dono = Arthur, mania = PertoDeObjeto Porta }
        , { dono = Joao, mania = NaCadeiraDe Tomada }
        , { dono = Mayara, mania = LongeDe Joao }
        , { dono = Bevi, mania = SemVizinhos }
        ]
    }


bevi : Bce.Lugar
bevi =
    lugar Bevi 1 1


lugar : Amigo -> Int -> Int -> Bce.Lugar
lugar amigo linha coluna =
    { amigo = amigo, posicao = { linha = linha, coluna = coluna } }
