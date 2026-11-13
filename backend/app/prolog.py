"""Ponte entre Python e Prolog usando a biblioteca janus.

janus (pacote `janus-swi`) embute o SWI-Prolog dentro do processo Python.
Não há servidor Prolog separado nem troca de mensagens: chamamos predicados
diretamente e recebemos as respostas como dicionários Python.

Conversão automática de tipos (Python -> Prolog):
    int          -> inteiro
    str          -> string  (use janus.Term / átomos com cuidado, veja abaixo)
    list         -> lista
    dict         -> dict do SWI-Prolog

Para mais detalhes: https://www.swi-prolog.org/pldoc/man?section=janus

Este é o ÚNICO arquivo do projeto que conhece o janus. O resto do backend
só chama as funções abaixo.
"""

from pathlib import Path

import janus_swi as janus

Grid = list[list[int]]

PROLOG_DIR = Path(__file__).parent.parent / "prolog"
PROLOG_FILE = PROLOG_DIR / "sudoku.pl"
BCE_API_FILE = PROLOG_DIR / "bce_api.pl"

# consult/1 carrega o arquivo .pl, como `?- [sudoku].` no terminal do swipl.
# bce_api.pl carrega o bce.pl sozinho (use_module).
janus.consult(str(PROLOG_FILE))
janus.consult(str(BCE_API_FILE))


class NoSolution(Exception):
    """O tabuleiro enviado não tem solução."""


class BoardComplete(Exception):
    """O tabuleiro não tem casas vazias: não há dica para dar."""


def solve(puzzle: Grid) -> Grid:
    # query_once executa a consulta e devolve um dict com as variáveis da
    # consulta (em maiúsculas, como no Prolog) e a chave 'truth', que diz se
    # a consulta teve sucesso.
    result = janus.query_once("sudoku:solve(Puzzle, Solution)", {"Puzzle": puzzle})
    if not result["truth"]:
        raise NoSolution
    return result["Solution"]


def generate(difficulty: str) -> Grid:
    # Strings do Python viram strings do Prolog, mas generate/2 espera um
    # ÁTOMO (easy, medium, hard). atom_string/2 faz a conversão do lado Prolog.
    result = janus.query_once(
        "atom_string(D, Name), sudoku:generate(D, Puzzle)", {"Name": difficulty}
    )
    return result["Puzzle"]


def hint(board: Grid) -> tuple[int, int, int]:
    result = janus.query_once("sudoku:hint(Board, Result)", {"Board": board})["Result"]
    # hint/2 sempre tem sucesso e devolve, em Result, uma lista [Linha,
    # Coluna, Valor] ou um dos átomos `complete` e `unsolvable` (átomos
    # chegam ao Python como strings). Quem decidiu o que aconteceu foi o
    # Prolog; aqui só traduzimos cada caso. O `match` do Python escolhe o
    # ramo pela FORMA do valor, parecido com o casamento de padrões do
    # Prolog e do Elm.
    match result:
        case "complete":
            raise BoardComplete
        case "unsolvable":
            raise NoSolution
        case [row, col, value]:
            return row, col, value
    raise ValueError(f"resultado inesperado de hint/2: {result!r}")


# ---------------------------------------------------------------------------
# Grupo de Estudo na BCE (prolog/bce_api.pl)
#
# Lugar = [nome, linha, coluna], usado para objetos, fixos e sentados.
# Os nomes vão como strings e o bce_api.pl os converte em átomos.
# ---------------------------------------------------------------------------

Lugar = list  # [str, int, int]


class InvalidState(Exception):
    """O estado enviado não pode existir (ver estado_valido/3 no bce.pl)."""


class InvalidMove(Exception):
    """A jogada não é permitida no estado atual."""


class PhaseComplete(Exception):
    """Todos os amigos já estão sentados: não há dica para dar."""


class PhaseUnsolvable(Exception):
    """Não existe solução a partir de quem já está sentado."""


class NoForcedMove(Exception):
    """Nenhuma jogada é obrigatória: mais de uma cadeira serve."""


def nova_fase(dificuldade: str) -> dict:
    result = janus.query_once(
        "bce_api:nova_fase(D, L, C, Objetos, Amigos, Fixos, Manias)",
        {"D": dificuldade},
    )
    return {
        "linhas": result["L"],
        "colunas": result["C"],
        "objetos": result["Objetos"],
        "amigos": result["Amigos"],
        "fixos": result["Fixos"],
        "manias": result["Manias"],
    }


def _resultado(result) -> tuple[list[Lugar], list[list[str]], bool]:
    # O Prolog decide o que aconteceu; aqui só traduzimos cada forma, como
    # em hint() acima. Átomos chegam como strings, inclusive true/false.
    match result:
        case "invalido":
            raise InvalidState
        case "jogada_invalida":
            raise InvalidMove
        case [sentados, status, venceu]:
            return sentados, status, venceu == "true"
    raise ValueError(f"resultado inesperado do bce_api: {result!r}")


def estado(
    linhas: int,
    colunas: int,
    objetos: list[Lugar],
    amigos: list[str],
    fixos: list[Lugar],
    sentados: list[Lugar],
) -> tuple[list[Lugar], list[list[str]], bool]:
    result = janus.query_once(
        "bce_api:estado(L, C, Objetos, Amigos, Fixos, Sentados, R)",
        {
            "L": linhas,
            "C": colunas,
            "Objetos": objetos,
            "Amigos": amigos,
            "Fixos": fixos,
            "Sentados": sentados,
        },
    )
    return _resultado(result["R"])


def jogada(
    linhas: int,
    colunas: int,
    objetos: list[Lugar],
    amigos: list[str],
    fixos: list[Lugar],
    sentados: list[Lugar],
    amigo: str,
    linha: int,
    coluna: int,
) -> tuple[list[Lugar], list[list[str]], bool]:
    result = janus.query_once(
        "bce_api:jogada(L, C, Objetos, Amigos, Fixos, Sentados,"
        " Amigo, Linha, Coluna, R)",
        {
            "L": linhas,
            "C": colunas,
            "Objetos": objetos,
            "Amigos": amigos,
            "Fixos": fixos,
            "Sentados": sentados,
            "Amigo": amigo,
            "Linha": linha,
            "Coluna": coluna,
        },
    )
    return _resultado(result["R"])


def dica(
    linhas: int,
    colunas: int,
    objetos: list[Lugar],
    amigos: list[str],
    fixos: list[Lugar],
    sentados: list[Lugar],
) -> tuple[str, int, int, list]:
    result = janus.query_once(
        "bce_api:dica(L, C, Objetos, Amigos, Fixos, Sentados, R)",
        {
            "L": linhas,
            "C": colunas,
            "Objetos": objetos,
            "Amigos": amigos,
            "Fixos": fixos,
            "Sentados": sentados,
        },
    )["R"]
    # Mesmo esquema de _resultado: cada átomo vira uma exceção e a lista
    # vira o retorno. Motivo é [] ou [amigo, tipo, args], ver dica/7.
    match result:
        case "invalido":
            raise InvalidState
        case "completo":
            raise PhaseComplete
        case "sem_solucao":
            raise PhaseUnsolvable
        case "sem_jogada":
            raise NoForcedMove
        case [amigo, linha, coluna, motivo]:
            return amigo, linha, coluna, motivo
    raise ValueError(f"resultado inesperado de dica/7: {result!r}")
