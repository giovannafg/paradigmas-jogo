"""Testes das rotas do Grupo de Estudo na BCE (pytest).

Como em test_api.py, conferimos só a "cola": rotas, formato do JSON e
códigos de status. As regras das manias são do Prolog (bce.pl).

Rodar: `uv run pytest` (na pasta backend) ou `make test-backend` (na raiz).
"""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

# A fase de exemplo de docs/REGRAS.md (fase_exemplo/3 em bce.pl): Bevi já
# sentado embaixo, no meio. Solução: Mayara (0,0), Arthur (0,1), João (0,2).
BEVI = {"amigo": "bevi", "linha": 1, "coluna": 1}
SOLUCAO = [
    {"amigo": "mayara", "linha": 0, "coluna": 0},
    {"amigo": "arthur", "linha": 0, "coluna": 1},
    {"amigo": "joao", "linha": 0, "coluna": 2},
    BEVI,
]


def nova_fase() -> dict:
    return client.post("/api/fase/nova", json={"dificuldade": "facil"}).json()


def status_de(resposta: dict) -> dict[str, str]:
    return {s["amigo"]: s["status"] for s in resposta["status"]}


def test_nova_fase():
    response = client.post("/api/fase/nova", json={"dificuldade": "facil"})
    assert response.status_code == 200
    fase = response.json()
    assert fase["mesa"]["linhas"] == 2 and fase["mesa"]["colunas"] == 3
    assert {"objeto": "porta", "linha": 0, "coluna": 0} in fase["mesa"]["objetos"]
    assert sorted(fase["amigos"]) == ["arthur", "bevi", "joao", "mayara"]
    assert fase["fixos"] == [BEVI]


def test_nova_fase_traz_as_manias():
    manias = {m["amigo"]: m for m in nova_fase()["manias"]}
    assert manias["arthur"] == {
        "amigo": "arthur",
        "tipo": "perto_de_objeto",
        "alvo": "porta",
    }
    assert manias["bevi"]["tipo"] == "sem_vizinhos"
    assert manias["bevi"]["alvo"] is None


def test_nova_fase_rejeita_dificuldade_desconhecida():
    response = client.post("/api/fase/nova", json={"dificuldade": "impossivel"})
    assert response.status_code == 422


def test_estado_inicial():
    response = client.post(
        "/api/fase/estado", json={"fase": nova_fase(), "sentados": [BEVI]}
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
        "/api/fase/estado", json={"fase": nova_fase(), "sentados": sentados}
    )
    assert status_de(response.json())["mayara"] == "violada"


def test_estado_vitoria():
    response = client.post(
        "/api/fase/estado", json={"fase": nova_fase(), "sentados": SOLUCAO}
    )
    assert response.json()["venceu"] is True


def test_estado_sem_o_fixo_e_invalido():
    response = client.post(
        "/api/fase/estado", json={"fase": nova_fase(), "sentados": []}
    )
    assert response.status_code == 422


def test_estado_com_amigo_desconhecido_e_invalido():
    fase = nova_fase()
    fase["amigos"].append("xuxa")
    response = client.post("/api/fase/estado", json={"fase": fase, "sentados": [BEVI]})
    assert response.status_code == 422


def test_jogada():
    jogada = {"amigo": "joao", "linha": 0, "coluna": 2}
    response = client.post(
        "/api/fase/jogada", json={"fase": nova_fase(), "sentados": [BEVI], **jogada}
    )
    assert response.status_code == 200
    estado = response.json()
    assert jogada in estado["sentados"]
    assert status_de(estado)["joao"] == "ok"


def test_jogada_vencedora():
    response = client.post(
        "/api/fase/jogada",
        json={
            "fase": nova_fase(),
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
            "fase": nova_fase(),
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
            "fase": nova_fase(),
            "sentados": [BEVI],
            "amigo": "joao",
            "linha": 5,
            "coluna": 5,
        },
    )
    assert response.status_code == 422
