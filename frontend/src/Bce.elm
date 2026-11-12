module Bce exposing
    ( Amigo(..)
    , Dica
    , Estrelas(..)
    , Fase
    , Lugar
    , Mania(..)
    , Objeto(..)
    , Posicao
    , Recusa(..)
    , Regra
    , Rodada(..)
    , Selecao(..)
    , StatusMania(..)
    , amigoDeTexto
    , amigoParaTexto
    , comArtigo
    , conflitos
    , descreverMania
    , estrelasPorDicas
    , explicarDica
    , levantar
    , maniaDeTexto
    , maniaParaTexto
    , nomeDoAmigo
    , objetoDeTexto
    , objetoEm
    , objetoParaTexto
    , ocupante
    , posicoes
    , recusaParaTexto
    , semAssento
    , sentar
    , statusDe
    , todosAmigos
    , todosObjetos
    , todosSentados
    )

{-| Domínio do jogo "Grupo de Estudo na BCE", do lado do Elm.

Este módulo é PURO: não faz HTTP e não sabe nada de HTML. São só tipos e
funções sobre eles, como o `Sudoku.elm` do template.

A ideia central é fazer o compilador trabalhar por nós. Cada pergunta do
jogo vira um _custom type_ com exatamente as respostas possíveis, e o `case`
obriga a tratar todas. Não há `String` solta para "qual amigo" nem `Bool`
para "qual estado da partida": um valor inválido nem chega a existir.

As regras das manias (quem está ✅ ou ❌) moram no Prolog. Aqui ficam só as
regras instantâneas, que não precisam do servidor: a cadeira está livre? o
amigo já sentou? todos sentaram? Quem decide se a mania está respeitada é o
`status` que a API devolve.

-}

-- AMIGOS E OBJETOS


{-| Os sete integrantes do grupo. Um custom type em vez de `String` porque a
lista é fechada: `case` sobre `Amigo` sem tratar a `Mayara` não compila.
-}
type Amigo
    = Arthur
    | Bevi
    | Felipe
    | Gabriel
    | Giovanna
    | Joao
    | Mayara


type Objeto
    = Janela
    | Tomada
    | Porta
    | Estante


todosAmigos : List Amigo
todosAmigos =
    [ Arthur, Bevi, Felipe, Gabriel, Giovanna, Joao, Mayara ]


todosObjetos : List Objeto
todosObjetos =
    [ Janela, Tomada, Porta, Estante ]


nomeDoAmigo : Amigo -> String
nomeDoAmigo amigo =
    case amigo of
        Arthur ->
            "Arthur"

        Bevi ->
            "Bevi"

        Felipe ->
            "Felipe"

        Gabriel ->
            "Gabriel"

        Giovanna ->
            "Giovanna"

        Joao ->
            "João"

        Mayara ->
            "Mayara"


{-| "o Arthur", "a Mayara": o artigo que a frase em português pede.
-}
comArtigo : Amigo -> String
comArtigo amigo =
    case amigo of
        Giovanna ->
            "a Giovanna"

        Mayara ->
            "a Mayara"

        _ ->
            "o " ++ nomeDoAmigo amigo


{-| Nome usado pela API (e pelo Prolog: são os átomos em minúsculas e sem
acento).
-}
amigoParaTexto : Amigo -> String
amigoParaTexto amigo =
    case amigo of
        Arthur ->
            "arthur"

        Bevi ->
            "bevi"

        Felipe ->
            "felipe"

        Gabriel ->
            "gabriel"

        Giovanna ->
            "giovanna"

        Joao ->
            "joao"

        Mayara ->
            "mayara"


{-| O caminho de volta devolve `Maybe`: um texto desconhecido vira `Nothing`,
e quem decodifica o JSON decide o que fazer com o erro.
-}
amigoDeTexto : String -> Maybe Amigo
amigoDeTexto texto =
    todosAmigos
        |> List.filter (\amigo -> amigoParaTexto amigo == texto)
        |> List.head


objetoParaTexto : Objeto -> String
objetoParaTexto objeto =
    case objeto of
        Janela ->
            "janela"

        Tomada ->
            "tomada"

        Porta ->
            "porta"

        Estante ->
            "estante"


objetoDeTexto : String -> Maybe Objeto
objetoDeTexto texto =
    todosObjetos
        |> List.filter (\objeto -> objetoParaTexto objeto == texto)
        |> List.head



-- POSIÇÕES, LUGARES E FASE


{-| Linhas e colunas começam em 0, com (0, 0) no canto de cima à esquerda,
igual ao contrato da API.
-}
type alias Posicao =
    { linha : Int
    , coluna : Int
    }


{-| Um amigo sentado numa cadeira.
-}
type alias Lugar =
    { amigo : Amigo
    , posicao : Posicao
    }


{-| O vocabulário de manias do REGRAS.md. Cada construtor carrega só o que
aquela mania precisa: `SemVizinhos` não tem alvo, `PertoDeObjeto` tem um
`Objeto` e `PertoDe` tem um `Amigo`. Com um record de campos opcionais seria
possível montar "perto de objeto" sem objeto; aqui isso não compila.
-}
type Mania
    = PertoDeObjeto Objeto
    | NaCadeiraDe Objeto
    | SemVizinhos
    | DeFrentePara (List Amigo)
    | PertoDe Amigo
    | LadoALadoCom Amigo
    | LongeDe Amigo


{-| Uma mania e de quem ela é.
-}
type alias Regra =
    { dono : Amigo
    , mania : Mania
    }


{-| O que não muda durante a partida. `linhas` e `colunas` dão o tamanho da
mesa; `fixos` são os amigos que já começam sentados.
-}
type alias Fase =
    { linhas : Int
    , colunas : Int
    , objetos : List ( Objeto, Posicao )
    , amigos : List Amigo
    , fixos : List Lugar
    , manias : List Regra
    }


{-| Todas as cadeiras da mesa, de cima para baixo e da esquerda para a
direita. A tela usa isto para desenhar a grade.
-}
posicoes : Fase -> List Posicao
posicoes fase =
    List.range 0 (fase.linhas - 1)
        |> List.concatMap
            (\linha ->
                List.range 0 (fase.colunas - 1)
                    |> List.map (\coluna -> { linha = linha, coluna = coluna })
            )


objetoEm : Fase -> Posicao -> Maybe Objeto
objetoEm fase posicao =
    fase.objetos
        |> List.filter (\( _, onde ) -> onde == posicao)
        |> List.head
        |> Maybe.map Tuple.first



-- SENTAR E LEVANTAR


{-| Por que uma jogada foi recusada. Cada motivo é um construtor, então a
tela pode explicar cada um sem comparar mensagens de texto.
-}
type Recusa
    = ForaDaMesa
    | CadeiraOcupada
    | JaSentado
    | NaoEstaSentado
    | AmigoFixo
    | AmigoForaDaFase


ocupante : List Lugar -> Posicao -> Maybe Amigo
ocupante sentados posicao =
    sentados
        |> List.filter (\lugar -> lugar.posicao == posicao)
        |> List.head
        |> Maybe.map .amigo


estaSentado : List Lugar -> Amigo -> Bool
estaSentado sentados amigo =
    List.any (\lugar -> lugar.amigo == amigo) sentados


dentroDaMesa : Fase -> Posicao -> Bool
dentroDaMesa fase posicao =
    List.member posicao (posicoes fase)


{-| Senta o amigo, ou diz por que não pode. `Result Recusa` obriga quem chama
a tratar o caso de erro, no lugar de uma exceção ou de um `Bool` ignorado.

As regras aqui são as "instantâneas": não precisam do servidor. Se a jogada
passar, o Elm ainda pergunta ao Prolog como ficaram as manias.

-}
sentar : Fase -> List Lugar -> Amigo -> Posicao -> Result Recusa (List Lugar)
sentar fase sentados amigo posicao =
    if not (List.member amigo fase.amigos) then
        Err AmigoForaDaFase

    else if estaSentado sentados amigo then
        Err JaSentado

    else if not (dentroDaMesa fase posicao) then
        Err ForaDaMesa

    else if ocupante sentados posicao /= Nothing then
        Err CadeiraOcupada

    else
        Ok (sentados ++ [ { amigo = amigo, posicao = posicao } ])


{-| Devolve o amigo para o lado da mesa. Os fixos não podem sair do lugar,
como os números dados do Sudoku.
-}
levantar : Fase -> List Lugar -> Amigo -> Result Recusa (List Lugar)
levantar fase sentados amigo =
    if List.any (\fixo -> fixo.amigo == amigo) fase.fixos then
        Err AmigoFixo

    else if not (estaSentado sentados amigo) then
        Err NaoEstaSentado

    else
        Ok (List.filter (\lugar -> lugar.amigo /= amigo) sentados)


{-| Os amigos da fase que ainda estão ao lado da mesa, na ordem da fase.
-}
semAssento : Fase -> List Lugar -> List Amigo
semAssento fase sentados =
    List.filter (\amigo -> not (estaSentado sentados amigo)) fase.amigos


todosSentados : Fase -> List Lugar -> Bool
todosSentados fase sentados =
    List.isEmpty (semAssento fase sentados)


recusaParaTexto : Recusa -> String
recusaParaTexto recusa =
    case recusa of
        ForaDaMesa ->
            "Essa cadeira não existe nesta mesa."

        CadeiraOcupada ->
            "Essa cadeira já está ocupada."

        JaSentado ->
            "Esse amigo já está sentado. Clique nele para levantá-lo."

        NaoEstaSentado ->
            "Esse amigo ainda não está sentado."

        AmigoFixo ->
            "Esse amigo já começou sentado e não pode sair do lugar."

        AmigoForaDaFase ->
            "Esse amigo não participa desta fase."



-- STATUS DAS MANIAS


{-| ✅, ❌ ou neutra. Um tipo com três casos no lugar de `Maybe Bool`: o
`Nothing` de um `Maybe Bool` não diz que significa "pendente".
-}
type StatusMania
    = Respeitada
    | Violada
    | Pendente


{-| Quem aparece com mania ❌, para a tela destacar.
-}
conflitos : List ( Amigo, StatusMania ) -> List Amigo
conflitos status =
    status
        |> List.filter (\( _, s ) -> s == Violada)
        |> List.map Tuple.first


{-| Sem informação do servidor a mania é `Pendente`, que é também o que a
tela mostra no início da fase.
-}
statusDe : List ( Amigo, StatusMania ) -> Amigo -> StatusMania
statusDe status amigo =
    status
        |> List.filter (\( quem, _ ) -> quem == amigo)
        |> List.head
        |> Maybe.map Tuple.second
        |> Maybe.withDefault Pendente



-- ESTADO DA PARTIDA


{-| O que está selecionado na tela. Evita um `Maybe Amigo`, em que `Nothing`
não diz nada: aqui o nome do caso explica.
-}
type Selecao
    = NadaSelecionado
    | AmigoSelecionado Amigo


type Estrelas
    = TresEstrelas
    | DuasEstrelas
    | UmaEstrela


{-| Em que ponto está a partida. A vitória carrega as estrelas, então é
impossível "ter vencido" sem nota, e impossível ter estrelas sem vencer.
-}
type Rodada
    = Jogando
    | Venceu Estrelas


{-| Proposta do REGRAS.md: ⭐⭐⭐ sem dicas, ⭐⭐ com 1 ou 2, ⭐ com 3 ou mais.
-}
estrelasPorDicas : Int -> Estrelas
estrelasPorDicas dicas =
    if dicas <= 0 then
        TresEstrelas

    else if dicas <= 2 then
        DuasEstrelas

    else
        UmaEstrela



-- DICA


{-| A jogada que o Prolog diz ser forçada. `motivo` é `Nothing` quando a
cadeira sobra só por eliminação, sem depender de nenhuma mania.
-}
type alias Dica =
    { amigo : Amigo
    , posicao : Posicao
    , motivo : Maybe Regra
    }


{-| Monta a frase da dica. O texto fica num lugar só (aqui), como combinado
no docs/API.md: o Prolog manda a mania, o Elm escreve a explicação.
-}
explicarDica : Dica -> String
explicarDica dica =
    let
        jogada =
            "Sente "
                ++ comArtigo dica.amigo
                ++ " na linha "
                ++ String.fromInt (dica.posicao.linha + 1)
                ++ ", coluna "
                ++ String.fromInt (dica.posicao.coluna + 1)
                ++ "."
    in
    case dica.motivo of
        Just regra ->
            descreverMania regra ++ " " ++ jogada

        Nothing ->
            "Só sobra uma cadeira possível por eliminação. " ++ jogada



-- TEXTO DAS MANIAS


{-| A mania numa frase, para o card do amigo: "O Arthur precisa ficar perto
da porta."
-}
descreverMania : Regra -> String
descreverMania { dono, mania } =
    capitaliza (comArtigo dono) ++ " " ++ predicado mania ++ "."


predicado : Mania -> String
predicado mania =
    case mania of
        PertoDeObjeto objeto ->
            "precisa ficar perto " ++ daObjeto objeto

        NaCadeiraDe objeto ->
            "precisa sentar na cadeira " ++ daObjeto objeto

        SemVizinhos ->
            "não pode ter ninguém sentado ao lado"

        DeFrentePara amigos ->
            "precisa sentar de frente para "
                ++ String.join " ou " (List.map comArtigo amigos)

        PertoDe amigo ->
            "precisa ficar perto " ++ deAmigo amigo

        LadoALadoCom amigo ->
            "precisa sentar ao lado " ++ deAmigo amigo

        LongeDe amigo ->
            "não pode ficar perto " ++ deAmigo amigo


{-| Todos os objetos são femininos: "da porta", "da tomada".
-}
daObjeto : Objeto -> String
daObjeto objeto =
    "da " ++ objetoParaTexto objeto


deAmigo : Amigo -> String
deAmigo amigo =
    "d" ++ comArtigo amigo


capitaliza : String -> String
capitaliza texto =
    case String.uncons texto of
        Just ( primeira, resto ) ->
            String.cons (Char.toUpper primeira) resto

        Nothing ->
            texto



-- MANIAS NO JSON
--
-- O Api.elm decodifica o JSON e usa estas duas funções para a parte que é
-- regra do domínio: `tipo` + `alvo` viram um `Mania`, e vice-versa. O `alvo`
-- chega como lista de textos (um objeto, um amigo, vários amigos ou nada).


maniaDeTexto : String -> List String -> Result String Mania
maniaDeTexto tipo alvo =
    case ( tipo, alvo ) of
        ( "perto_de_objeto", [ objeto ] ) ->
            objetoOuErro objeto |> Result.map PertoDeObjeto

        ( "na_cadeira_de", [ objeto ] ) ->
            objetoOuErro objeto |> Result.map NaCadeiraDe

        ( "sem_vizinhos", [] ) ->
            Ok SemVizinhos

        ( "de_frente_para_algum", amigos ) ->
            amigos
                |> List.map amigoOuErro
                |> combina
                |> Result.map DeFrentePara

        ( "perto_de", [ amigo ] ) ->
            amigoOuErro amigo |> Result.map PertoDe

        ( "lado_a_lado_com", [ amigo ] ) ->
            amigoOuErro amigo |> Result.map LadoALadoCom

        ( "longe_de", [ amigo ] ) ->
            amigoOuErro amigo |> Result.map LongeDe

        _ ->
            Err ("Mania desconhecida: " ++ tipo)


maniaParaTexto : Mania -> ( String, List String )
maniaParaTexto mania =
    case mania of
        PertoDeObjeto objeto ->
            ( "perto_de_objeto", [ objetoParaTexto objeto ] )

        NaCadeiraDe objeto ->
            ( "na_cadeira_de", [ objetoParaTexto objeto ] )

        SemVizinhos ->
            ( "sem_vizinhos", [] )

        DeFrentePara amigos ->
            ( "de_frente_para_algum", List.map amigoParaTexto amigos )

        PertoDe amigo ->
            ( "perto_de", [ amigoParaTexto amigo ] )

        LadoALadoCom amigo ->
            ( "lado_a_lado_com", [ amigoParaTexto amigo ] )

        LongeDe amigo ->
            ( "longe_de", [ amigoParaTexto amigo ] )


amigoOuErro : String -> Result String Amigo
amigoOuErro texto =
    amigoDeTexto texto
        |> Result.fromMaybe ("Amigo desconhecido: " ++ texto)


objetoOuErro : String -> Result String Objeto
objetoOuErro texto =
    objetoDeTexto texto
        |> Result.fromMaybe ("Objeto desconhecido: " ++ texto)


{-| Junta uma lista de `Result` num único: o primeiro erro vence.
-}
combina : List (Result e a) -> Result e (List a)
combina =
    List.foldr (Result.map2 (::)) (Ok [])
