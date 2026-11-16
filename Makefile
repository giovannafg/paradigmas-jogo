# Atalhos para as tarefas mais comuns. Uso: `make <alvo>`.
#
# O `make` só interpreta as linhas de receita (indentadas com TAB), cada uma
# executada num shell separado; por isso usamos `cd pasta && comando`.

.PHONY: install dev backend frontend test test-prolog test-backend test-frontend validar

install:            ## instala as dependências do backend e do frontend
	cd backend && uv sync
	cd frontend && npm install

dev:                ## sobe backend e frontend juntos (Ctrl+C encerra ambos)
	$(MAKE) -j2 backend frontend

backend:            ## só o backend: http://localhost:8000/docs
	cd backend && uv run fastapi dev app/main.py

frontend:           ## só o frontend: http://localhost:5173
	cd frontend && npm run dev

test: test-prolog test-backend test-frontend

test-prolog:
	swipl -g run_tests -t halt backend/prolog/test_sudoku.pl
	swipl -g run_tests -t halt backend/prolog/test_bce.pl

test-backend:
	cd backend && uv run pytest

test-frontend:
	cd frontend && npx elm-test

validar:            ## confere a forma do RELATORIO.md e das avaliações 360
	uv run scripts/validar_entrega.py
