PYTHON ?= python3
VENV ?= backend/.venv
UVICORN ?= $(VENV)/bin/uvicorn
PIP ?= $(VENV)/bin/pip

.PHONY: backend-install backend-up backend-run backend-check flutter-bootstrap

backend-install:
	cd backend && $(PYTHON) -m venv .venv && .venv/bin/pip install -r requirements.txt

backend-up:
	cd backend && docker compose up -d

backend-run:
	cd backend && . .venv/bin/activate && uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

backend-check:
	curl -fsS http://localhost:8000/api/v1/health && echo
	curl -fsS http://localhost:8000/api/v1/exercises && echo

flutter-bootstrap:
	cd flutter_app && flutter create .
	cd flutter_app && flutter pub get
