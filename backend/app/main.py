"""API HTTP da Mesa da BCE.

Esta camada é só "cola": recebe JSON, valida o formato com Pydantic, chama o
Prolog (via app/prolog.py) e devolve JSON. Nenhuma regra do jogo mora aqui.

Rodar em modo de desenvolvimento (recarrega ao salvar):
    uv run fastapi dev app/main.py

Documentação interativa gerada automaticamente: http://localhost:8000/docs
"""

from typing import Annotated, Literal

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from app import prolog

app = FastAPI(title="Mesa da BCE (Prolog + Elm)")

# O formato do JSON está descrito em docs/API.md. Os modelos abaixo são esse
# formato: o FastAPI valida as requisições com eles e os mostra em /docs.
Coordenada = Annotated[int, Field(ge=0)]
Dificuldade = Literal["facil", "medio", "dificil"]
StatusMania = Literal["ok", "violada", "pendente"]


class Objeto(BaseModel):
    objeto: str
    linha: Coordenada
    coluna: Coordenada


class Lugar(BaseModel):
    amigo: str
    linha: Coordenada
    coluna: Coordenada


class Mesa(BaseModel):
    linhas: Annotated[int, Field(ge=1, le=6)]
    colunas: Annotated[int, Field(ge=1, le=6)]
    objetos: list[Objeto]


class Mania(BaseModel):
    amigo: str
    tipo: str
    # Um objeto ("porta"), um amigo ("joao"), uma lista de amigos
    # (["arthur", "joao"]) ou nada, conforme o tipo. Ver docs/API.md.
    alvo: str | list[str] | None = None


class Fase(BaseModel):
    mesa: Mesa
    amigos: list[str]
    fixos: list[Lugar]
    # As manias vêm do Prolog só para o Elm mostrar nos cards. Se o Elm
    # mandar de volta, são ignoradas: quem decide as manias é o mania/2.
    manias: list[Mania] = []


class NovaFaseRequest(BaseModel):
    dificuldade: Dificuldade = "facil"


class EstadoRequest(BaseModel):
    fase: Fase
    sentados: list[Lugar]


class JogadaRequest(BaseModel):
    fase: Fase
    sentados: list[Lugar]
    amigo: str
    linha: Coordenada
    coluna: Coordenada


class Status(BaseModel):
    amigo: str
    status: StatusMania


class EstadoResponse(BaseModel):
    sentados: list[Lugar]
    status: list[Status]
    venceu: bool


class DicaResponse(BaseModel):
    amigo: str
    linha: int
    coluna: int
    # A mania que força a jogada; None quando só a mesa a força. O Elm monta
    # a frase a partir dela (docs/API.md).
    motivo: Mania | None


INVALID_STATE = "Este estado não existe no jogo. Confira a mesa e quem está sentado."
INVALID_MOVE = (
    "Essa jogada não é permitida: a cadeira está ocupada ou fora da mesa, "
    "ou o amigo já sentou ou não está nesta fase."
)
PHASE_COMPLETE = "Todo mundo já está sentado."
PHASE_UNSOLVABLE = (
    "Não dá para terminar a fase a partir daqui. Levante algum amigo e tente de novo."
)
NO_FORCED_MOVE = "Nenhuma jogada é obrigatória agora: mais de uma cadeira serve."


def _lugares(lugares: list[Lugar]) -> list[list]:
    return [[lugar.amigo, lugar.linha, lugar.coluna] for lugar in lugares]


def _argumentos_da_fase(fase: Fase) -> dict:
    return {
        "linhas": fase.mesa.linhas,
        "colunas": fase.mesa.colunas,
        "objetos": [[o.objeto, o.linha, o.coluna] for o in fase.mesa.objetos],
        "amigos": fase.amigos,
        "fixos": _lugares(fase.fixos),
    }


def _mania(amigo: str, tipo: str, args: list) -> Mania:
    # Args é [] (sem alvo) ou [alvo]: ver nova_fase/7 em bce_api.pl.
    return Mania(amigo=amigo, tipo=tipo, alvo=args[0] if args else None)


def _estado_response(resultado) -> EstadoResponse:
    sentados, status, venceu = resultado
    return EstadoResponse(
        sentados=[Lugar(amigo=a, linha=l, coluna=c) for a, l, c in sentados],
        status=[Status(amigo=a, status=s) for a, s in status],
        venceu=venceu,
    )


@app.post("/api/fase/nova")
def nova_fase(request: NovaFaseRequest) -> Fase:
    fase = prolog.nova_fase(request.dificuldade)
    return Fase(
        mesa=Mesa(
            linhas=fase["linhas"],
            colunas=fase["colunas"],
            objetos=[
                Objeto(objeto=o, linha=l, coluna=c) for o, l, c in fase["objetos"]
            ],
        ),
        amigos=fase["amigos"],
        fixos=[Lugar(amigo=a, linha=l, coluna=c) for a, l, c in fase["fixos"]],
        manias=[_mania(a, t, args) for a, t, args in fase["manias"]],
    )


@app.post("/api/fase/estado")
def estado(request: EstadoRequest) -> EstadoResponse:
    try:
        resultado = prolog.estado(
            **_argumentos_da_fase(request.fase), sentados=_lugares(request.sentados)
        )
    except prolog.InvalidState:
        # `from None` diz que a HTTPException SUBSTITUI a exceção original,
        # em vez de ser "causada" por ela; o traceback fica mais limpo.
        raise HTTPException(status_code=422, detail=INVALID_STATE) from None
    return _estado_response(resultado)


@app.post("/api/fase/jogada")
def jogada(request: JogadaRequest) -> EstadoResponse:
    try:
        resultado = prolog.jogada(
            **_argumentos_da_fase(request.fase),
            sentados=_lugares(request.sentados),
            amigo=request.amigo,
            linha=request.linha,
            coluna=request.coluna,
        )
    except prolog.InvalidState:
        raise HTTPException(status_code=422, detail=INVALID_STATE) from None
    except prolog.InvalidMove:
        raise HTTPException(status_code=422, detail=INVALID_MOVE) from None
    return _estado_response(resultado)


@app.post("/api/fase/dica")
def dica(request: EstadoRequest) -> DicaResponse:
    try:
        amigo, linha, coluna, motivo = prolog.dica(
            **_argumentos_da_fase(request.fase), sentados=_lugares(request.sentados)
        )
    except prolog.InvalidState:
        raise HTTPException(status_code=422, detail=INVALID_STATE) from None
    except prolog.PhaseComplete:
        raise HTTPException(status_code=422, detail=PHASE_COMPLETE) from None
    except prolog.PhaseUnsolvable:
        raise HTTPException(status_code=422, detail=PHASE_UNSOLVABLE) from None
    except prolog.NoForcedMove:
        raise HTTPException(status_code=422, detail=NO_FORCED_MOVE) from None
    return DicaResponse(
        amigo=amigo,
        linha=linha,
        coluna=coluna,
        motivo=_mania(*motivo) if motivo else None,
    )


@app.post("/api/fase/resolver")
def resolver(request: EstadoRequest) -> EstadoResponse:
    try:
        resultado = prolog.resolver(
            **_argumentos_da_fase(request.fase), sentados=_lugares(request.sentados)
        )
    except prolog.InvalidState:
        raise HTTPException(status_code=422, detail=INVALID_STATE) from None
    except prolog.PhaseUnsolvable:
        raise HTTPException(status_code=422, detail=PHASE_UNSOLVABLE) from None
    return _estado_response(resultado)
