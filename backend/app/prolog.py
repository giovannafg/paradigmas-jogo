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

PROLOG_DIR = Path(__file__).parent.parent / "prolog"
BCE_API_FILE = PROLOG_DIR / "bce_api.pl"

# consult/1 carrega o arquivo .pl, como `?- [bce_api].` no terminal do swipl.
# O bce_api.pl carrega o bce.pl sozinho (use_module).
janus.consult(str(BCE_API_FILE))

# Lugar = [nome, linha, coluna], usado para objetos, fixos e sentados.
# Os nomes vão como strings e o bce_api.pl os converte em átomos.
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
    # query_once executa a consulta e devolve um dict com as variáveis da
    # consulta (em maiúsculas, como no Prolog) e a chave 'truth', que diz se
    # a consulta teve sucesso.
    result = janus.query_once(
        "bce_api:nova_fase(D, L, C, Objetos, Amigos, Fixos, Manias)",
        {"D": dificuldade},
    )
    # generate/4 desiste depois de 50 tentativas; é raro, mas aí a consulta
    # falha e não há variáveis para ler.
    if not result["truth"]:
        raise RuntimeError(f"o gerador não achou uma fase {dificuldade!r}")
    return {
        "linhas": result["L"],
        "colunas": result["C"],
        "objetos": result["Objetos"],
        "amigos": result["Amigos"],
        "fixos": result["Fixos"],
        "manias": result["Manias"],
    }


def _resultado(result) -> tuple[list[Lugar], list[list[str]], bool]:
    # O Prolog decide o que aconteceu; aqui só traduzimos cada forma. O
    # `match` do Python escolhe o ramo pela FORMA do valor, parecido com o
    # casamento de padrões do Prolog e do Elm. Átomos chegam como strings,
    # inclusive true/false.
    match result:
        case "invalido":
            raise InvalidState
        case "jogada_invalida":
            raise InvalidMove
        case "sem_solucao":
            raise PhaseUnsolvable
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
    # Mesmo esquema do _resultado: cada átomo vira uma exceção e a lista
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


def resolver(
    linhas: int,
    colunas: int,
    objetos: list[Lugar],
    amigos: list[str],
    fixos: list[Lugar],
    sentados: list[Lugar],
) -> tuple[list[Lugar], list[list[str]], bool]:
    result = janus.query_once(
        "bce_api:resolver(L, C, Objetos, Amigos, Fixos, Sentados, R)",
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
