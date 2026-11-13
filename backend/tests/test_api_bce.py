"""Testes das rotas do Grupo de Estudo na BCE (pytest).

Como em test_api.py, conferimos só a "cola": rotas, formato do JSON e
códigos de status. As regras das manias são do Prolog (bce.pl).

Rodar: `uv run pytest` (na pasta backend) ou `make test-backend` (na raiz).
"""

import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

# A fase de exemplo de docs/REGRAS.md (fase_exemplo/3 em bce.pl): Bevi já
# sentado embaixo, no meio. Solução: Mayara (0,0), Arthur (0,1), João (0,2).
# Fica escrita aqui porque /api/fase/nova sorteia uma fase diferente a cada
# chamada (generate/4).
BEVI = {"amigo": "bevi", "linha": 1, "coluna": 1}
FASE = {
    "mesa": {
        "linhas": 2,
        "colunas": 3,
        "objetos": [
            {"objeto": "porta", "linha": 0, "coluna": 0},
            {"objeto": "tomada", "linha": 0, "coluna": 2},
        ],
    },
    "amigos": ["arthur", "joao", "mayara", "bevi"],
    "fixos": [BEVI],
}
SOLUCAO = [
    {"amigo": "mayara", "linha": 0, "coluna": 0},
    {"amigo": "arthur", "linha": 0, "coluna": 1},
    {"amigo": "joao", "linha": 0, "coluna": 2},
    BEVI,
]


def status_de(resposta: dict) -> dict[str, str]:
    return {s["amigo"]: s["status"] for s in resposta["status"]}


# Tamanho da mesa e número de amigos de cada nível (nivel/5 em bce.pl).
NIVEIS = {"facil": (2, 3, 4), "medio": (3, 3, 5), "dificil": (3, 4, 7)}


@pytest.mark.parametrize("dificuldade", NIVEIS)
def test_nova_fase(dificuldade):
    response = client.post("/api/fase/nova", json={"dificuldade": dificuldade})
    assert response.status_code == 200
    fase = response.json()
    linhas, colunas, num_amigos = NIVEIS[dificuldade]
    assert fase["mesa"]["linhas"] == linhas
    assert fase["mesa"]["colunas"] == colunas
    assert len(fase["amigos"]) == num_amigos
    assert {f["amigo"] for f in fase["fixos"]} <= set(fase["amigos"])
    assert {m["amigo"] for m in fase["manias"]} == set(fase["amigos"])


def test_nova_fase_comeca_valida():
    fase = client.post("/api/fase/nova", json={"dificuldade": "facil"}).json()
    response = client.post(
        "/api/fase/estado", json={"fase": fase, "sentados": fase["fixos"]}
    )
    assert response.status_code == 200
    assert response.json()["venceu"] is False


def test_nova_fase_rejeita_dificuldade_desconhecida():
    response = client.post("/api/fase/nova", json={"dificuldade": "impossivel"})
    assert response.status_code == 422


def test_estado_inicial():
    response = client.post(
        "/api/fase/estado", json={"fase": FASE, "sentados": [BEVI]}
    )
    assert response.status_code == 200
    estado = response.json()
    assert estado["venceu"] is False
    assert status_de(estado) == {
        "arthur": "pendente",
        "joao": "pendente",
        "mayara": "pendente",
        "bevi": "ok",
    }


def test_estado_com_mania_violada():
    sentados = [
        {"amigo": "mayara", "linha": 0, "coluna": 1},
        {"amigo": "joao", "linha": 0, "coluna": 2},
        BEVI,
    ]
    response = client.post(
        "/api/fase/estado", json={"fase": FASE, "sentados": sentados}
    )
    assert status_de(response.json())["mayara"] == "violada"


def test_estado_vitoria():
    response = client.post(
        "/api/fase/estado", json={"fase": FASE, "sentados": SOLUCAO}
    )
    assert response.json()["venceu"] is True


def test_estado_sem_o_fixo_e_invalido():
    response = client.post(
        "/api/fase/estado", json={"fase": FASE, "sentados": []}
    )
    assert response.status_code == 422


def test_estado_com_amigo_desconhecido_e_invalido():
    fase = {**FASE, "amigos": [*FASE["amigos"], "xuxa"]}
    response = client.post("/api/fase/estado", json={"fase": fase, "sentados": [BEVI]})
    assert response.status_code == 422


def test_jogada():
    jogada = {"amigo": "joao", "linha": 0, "coluna": 2}
    response = client.post(
        "/api/fase/jogada", json={"fase": FASE, "sentados": [BEVI], **jogada}
    )
    assert response.status_code == 200
    estado = response.json()
    assert jogada in estado["sentados"]
    assert status_de(estado)["joao"] == "ok"


def test_jogada_vencedora():
    response = client.post(
        "/api/fase/jogada",
        json={
            "fase": FASE,
            "sentados": SOLUCAO[1:],
            "amigo": "mayara",
            "linha": 0,
            "coluna": 0,
        },
    )
    assert response.json()["venceu"] is True


def test_jogada_em_cadeira_ocupada():
    response = client.post(
        "/api/fase/jogada",
        json={
            "fase": FASE,
            "sentados": [BEVI],
            "amigo": "joao",
            "linha": 1,
            "coluna": 1,
        },
    )
    assert response.status_code == 422
    assert "não é permitida" in response.json()["detail"]


def test_jogada_fora_da_mesa():
    response = client.post(
        "/api/fase/jogada",
        json={
            "fase": FASE,
            "sentados": [BEVI],
            "amigo": "joao",
            "linha": 5,
            "coluna": 5,
        },
    )
    assert response.status_code == 422


def test_dica():
    response = client.post("/api/fase/dica", json={"fase": FASE, "sentados": [BEVI]})
    assert response.status_code == 200
    assert response.json() == {
        "amigo": "joao",
        "linha": 0,
        "coluna": 2,
        "motivo": {"amigo": "joao", "tipo": "na_cadeira_de", "alvo": "tomada"},
    }


def test_dica_sem_motivo():
    # Só sobra uma cadeira para o João: quem força a jogada é a mesa.
    fase = {
        "mesa": {
            "linhas": 1,
            "colunas": 2,
            "objetos": [
                {"objeto": "porta", "linha": 0, "coluna": 0},
                {"objeto": "tomada", "linha": 0, "coluna": 1},
            ],
        },
        "amigos": ["arthur", "joao"],
        "fixos": [],
    }
    sentados = [{"amigo": "arthur", "linha": 0, "coluna": 0}]
    response = client.post("/api/fase/dica", json={"fase": fase, "sentados": sentados})
    assert response.status_code == 200
    assert response.json()["motivo"] is None


def test_dica_com_fase_completa():
    response = client.post("/api/fase/dica", json={"fase": FASE, "sentados": SOLUCAO})
    assert response.status_code == 422
    assert response.json()["detail"] == "Todo mundo já está sentado."


def test_dica_sem_solucao():
    sentados = [BEVI, {"amigo": "mayara", "linha": 0, "coluna": 1}]
    response = client.post("/api/fase/dica", json={"fase": FASE, "sentados": sentados})
    assert response.status_code == 422
    assert "Não dá para terminar" in response.json()["detail"]


def test_dica_com_estado_invalido():
    response = client.post("/api/fase/dica", json={"fase": FASE, "sentados": []})
    assert response.status_code == 422
    assert "não existe no jogo" in response.json()["detail"]


def test_dica_com_coordenada_negativa():
    sentados = [{"amigo": "bevi", "linha": -1, "coluna": 1}]
    response = client.post("/api/fase/dica", json={"fase": FASE, "sentados": sentados})
    assert response.status_code == 422
    # Erro do Pydantic: o formato nem chega ao Prolog, e detail é uma lista.
    assert isinstance(response.json()["detail"], list)


def test_resolver():
    response = client.post(
        "/api/fase/resolver", json={"fase": FASE, "sentados": [BEVI]}
    )
    assert response.status_code == 200
    estado = response.json()
    assert estado["venceu"] is True
    assert sorted(estado["sentados"], key=lambda l: l["amigo"]) == sorted(
        SOLUCAO, key=lambda l: l["amigo"]
    )


def test_resolver_fase_completa():
    response = client.post(
        "/api/fase/resolver", json={"fase": FASE, "sentados": SOLUCAO}
    )
    assert response.status_code == 200
    assert response.json()["venceu"] is True


def test_resolver_sem_solucao():
    sentados = [BEVI, {"amigo": "mayara", "linha": 0, "coluna": 1}]
    response = client.post(
        "/api/fase/resolver", json={"fase": FASE, "sentados": sentados}
    )
    assert response.status_code == 422
    assert "Não dá para terminar" in response.json()["detail"]


def test_resolver_com_estado_invalido():
    response = client.post("/api/fase/resolver", json={"fase": FASE, "sentados": []})
    assert response.status_code == 422
    assert "não existe no jogo" in response.json()["detail"]
