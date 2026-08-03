.PHONY: init up down logs proxy-up data-up git-up ai-up obs-up

init:
	bash scripts/bootstrap.sh

# 전체 모듈 순차 가동
up: init
	docker compose -f docker/proxy/docker-compose.yml --env-file .env up -d
	docker compose -f docker/data/docker-compose.yml --env-file .env up -d
	docker compose -f docker/git/docker-compose.yml --env-file .env up -d
	docker compose -f docker/ai/docker-compose.yml --env-file .env up -d
	docker compose -f docker/observability/docker-compose.yml --env-file .env up -d

# 개별 모듈 제어
data-up:
	docker compose -f docker/data/docker-compose.yml --env-file .env up -d

ai-up:
	docker compose -f docker/ai/docker-compose.yml --env-file .env up -d

# 전체 스택 종료
down:
	docker compose -f docker/observability/docker-compose.yml down
	docker compose -f docker/ai/docker-compose.yml down
	docker compose -f docker/git/docker-compose.yml down
	docker compose -f docker/data/docker-compose.yml down
	docker compose -f docker/proxy/docker-compose.yml down

logs:
	docker compose -f docker/proxy/docker-compose.yml logs -f
