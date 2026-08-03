#!/usr/bin/env bash
set -e

echo "=== 온프레미스 스택 초기화 시작 ==="

# 1. .env 파일 생성
if [ ! -f .env ]; then
  echo "[+] .env 파일이 없어 .env.example에서 복사합니다."
  cp .env.example .env
fi

# 2. 공유 네트워크 생성
if ! docker network inspect onprem-net >/dev/null 2>&1; then
  echo "[+] 공통 Docker 네트워크 'onprem-net' 생성 중..."
  docker network create onprem-net
else
  echo "[=] 네트워크 'onprem-net' 이미 존재함."
fi

echo "=== 초기화 완료 ==="
