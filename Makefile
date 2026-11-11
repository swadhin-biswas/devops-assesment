UV ?= uv
IMAGE ?= devops-task-app
TAG ?= local

.PHONY: help sync run test coverage lint build up down logs size

help:
	@printf '%s\n' \
		'make sync      Install locked dependencies with uv' \
		'make run       Run the app on APP_PORT (default 8080)' \
		'make test      Run tests' \
		'make coverage  Run tests with coverage' \
		'make lint      Run ruff' \
		'make build     Build the container image' \
		'make up        Start the app with Compose' \
		'make down      Stop the app' \
		'make logs      Follow app logs' \
		'make size      Show the local image size'

sync:
	$(UV) sync --frozen

run: sync
	$(UV) run python -m app

test: sync
	$(UV) run pytest

coverage: sync
	$(UV) run pytest --cov=app --cov-report=term-missing

lint: sync
	$(UV) run ruff check .

build:
	docker build \
		--build-arg APP_VERSION=$${APP_VERSION:-0.1.0} \
		--build-arg VCS_REF=$$(git rev-parse --short HEAD 2>/dev/null || echo local) \
		--build-arg BUILD_DATE=$$(date -u +%Y-%m-%dT%H:%M:%SZ) \
		-t $(IMAGE):$(TAG) .

up:
	docker compose up -d --build

down:
	docker compose down

logs:
	docker compose logs -f app

size:
	docker images --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}' | grep -E 'REPOSITORY|$(IMAGE)'
