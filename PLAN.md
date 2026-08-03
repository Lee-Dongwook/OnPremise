# 온프레미스 환경 구축 계획 (PLAN)

## 1. 목표와 원칙

이 레포지토리는 **외부 SaaS/클라우드 서비스에 의존하지 않고**, 단일 머신 위에서
개발에 필요한 전 과정(코드 관리 → 빌드/배포 → 실행 → 관측 → AI/데이터 활용)을
자체 호스팅으로 구성하는 것을 목표로 한다.

### 핵심 원칙

- **Self-hosted first** — GitHub, Docker Hub, OpenAI 등 외부 서비스를 기본값으로 쓰지 않는다.
- **Docker Compose 중심** — 단일 머신에서 재현 가능하고 이해하기 쉬운 방식으로 구성한다.
- **오프라인 재현성** — 인터넷이 끊겨도 (이미지가 로컬에 있으면) 전체 스택이 기동되도록 지향한다.
- **모듈화** — 각 서비스는 독립된 Compose 스택으로 분리하고, 공통 네트워크로 연결한다.
- **비밀정보 로컬 관리** — 외부 시크릿 매니저 대신 `.env` + 로컬 Vault(선택)로 관리한다.

### 대상 환경

- 단일 머신 (개인/학습용)
- 오케스트레이션: Docker Compose (Kubernetes는 범위 외, 향후 k3s 확장 여지만 남김)

---

## 2. 전체 아키텍처 개요

```
                    ┌──────────────────────────────────────────┐
                    │              단일 호스트 머신               │
                    │                                            │
  사용자 ──▶ Reverse Proxy (Traefik/Caddy) ──▶ 각 서비스 라우팅   │
                    │      *.local 도메인 / 로컬 TLS             │
                    │                                            │
   ┌────────────────┼──────────────┬──────────────┬────────────┐
   │  개발 인프라     │   런타임 백엔드 │   관측성       │   AI/데이터  │
   │  - Gitea       │  - PostgreSQL │  - Prometheus │  - Ollama   │
   │  - Registry    │  - Redis      │  - Grafana    │  - OpenWebUI│
   │  - CI Runner   │  - MinIO(S3)  │  - Loki       │  - Qdrant   │
   └────────────────┴──────────────┴──────────────┴────────────┘
                    │      공통 Docker 네트워크 (onprem-net)      │
                    └──────────────────────────────────────────┘
```

모든 스택은 공통 외부 네트워크 `onprem-net`에 연결되어 서로 통신한다.

---

## 3. 구성 요소 선택 (외부 서비스 대체)

| 영역                | 외부 서비스 (지양)  | 온프레미스 대체 (채택)                 | 비고                                        |
| ------------------- | ------------------- | -------------------------------------- | ------------------------------------------- |
| 코드 저장소         | GitHub/GitLab.com   | **Gitea**                              | 경량, 단일 바이너리, 패키지 레지스트리 내장 |
| CI/CD               | GitHub Actions      | **Gitea Actions** (self-hosted runner) | Actions 문법 호환                           |
| 컨테이너 레지스트리 | Docker Hub          | **Registry v2** 또는 Gitea 내장        | 로컬 이미지 push/pull                       |
| 리버스 프록시       | Cloudflare          | **Traefik** 또는 **Caddy**             | 로컬 도메인 + 자체 서명 TLS                 |
| 관계형 DB           | RDS 등              | **PostgreSQL**                         | pgvector 확장으로 벡터도 커버 가능          |
| 캐시/큐             | ElastiCache         | **Redis**                              |                                             |
| 오브젝트 스토리지   | AWS S3              | **MinIO**                              | S3 호환 API                                 |
| 로컬 LLM            | OpenAI API          | **Ollama** + **Open WebUI**            | 로컬 추론                                   |
| 벡터 DB             | Pinecone            | **Qdrant** (또는 pgvector)             | RAG 용                                      |
| 모니터링            | Datadog             | **Prometheus + Grafana**               | 메트릭/대시보드                             |
| 로그                | CloudWatch          | **Loki + Promtail**                    | 로그 수집                                   |
| 비밀 관리           | AWS Secrets Manager | `.env` (+ 선택적 **Vault**)            | 로컬 관리                                   |
| 로컬 DNS            | Route53             | **dnsmasq** 또는 hosts 파일            | `*.local` 해석                              |

> 각 항목은 Phase별로 점진 도입한다. 처음부터 전부 띄우지 않는다.

---

## 4. 제안 디렉터리 구조

```
onprem/
├── README.md
├── PLAN.md                     # 이 문서
├── Makefile                    # up/down/logs 등 공통 명령
├── .env.example                # 공통 환경변수 템플릿 (비밀값은 커밋 금지)
├── docker/
│   ├── network.yml             # 공통 네트워크 onprem-net 정의
│   ├── proxy/                   # Traefik/Caddy 리버스 프록시
│   ├── git/                     # Gitea + Actions runner
│   ├── registry/                # 컨테이너 레지스트리
│   ├── data/                    # PostgreSQL, Redis, MinIO
│   ├── observability/           # Prometheus, Grafana, Loki
│   └── ai/                      # Ollama, Open WebUI, Qdrant
├── scripts/
│   ├── bootstrap.sh             # 초기 준비 (네트워크, 볼륨, hosts)
│   ├── backup.sh                # 볼륨/DB 백업
│   └── restore.sh
└── docs/
    ├── setup.md                 # 설치 절차
    ├── runbook.md               # 운영/장애 대응
    └── decisions/               # ADR (아키텍처 결정 기록)
```

각 서비스 폴더는 자체 `docker-compose.yml`과 `.env`, 필요한 설정 파일을 갖는다.

---

## 5. 단계별 로드맵 (Phases)

### Phase 0 — 기반 (Foundation)

- [ ] 호스트 요구사항 정의 (CPU/RAM/디스크, Docker/Compose 버전)
- [ ] 공통 네트워크 `onprem-net` 생성 스크립트
- [ ] `.env.example`, `Makefile`, `bootstrap.sh` 뼈대
- [ ] 로컬 도메인 전략 결정 (dnsmasq vs hosts, `*.local` vs `*.lan`)

### Phase 1 — 리버스 프록시 & 진입점

- [ ] Traefik(또는 Caddy) 스택 구성
- [ ] 자체 서명 TLS 또는 mkcert 로컬 CA
- [ ] 대시보드 접근 확인 (`proxy.local`)

### Phase 2 — 개발 인프라

- [ ] Gitea 기동 + 초기 관리자/조직 생성 (`git.local`)
- [ ] 컨테이너 레지스트리 구성 + 프록시 연동 (`registry.local`)
- [ ] Gitea Actions runner 등록 + 샘플 CI 파이프라인

### Phase 3 — 런타임 백엔드

- [ ] PostgreSQL (+ pgvector 확장)
- [ ] Redis
- [ ] MinIO (S3 호환, `minio.local` 콘솔)
- [ ] 백업/복구 스크립트 (`backup.sh`)

### Phase 4 — 관측성

- [ ] Prometheus + node/cadvisor exporter
- [ ] Grafana (대시보드 프로비저닝, `grafana.local`)
- [ ] Loki + Promtail 로그 수집

### Phase 5 — AI/데이터

- [ ] Ollama (로컬 LLM 서빙) + 모델 pull
- [ ] Open WebUI (`chat.local`)
- [ ] Qdrant 또는 pgvector 기반 RAG 예제

### Phase 6 — 통합 & 예제

- [ ] 샘플 웹/앱 서비스: Git push → CI 빌드 → 레지스트리 push → 배포
- [ ] end-to-end 시나리오 문서화
- [ ] 전체 스택 up/down 원커맨드 (`make up` / `make down`)

---

## 6. 공통 규약

- **네트워크**: 모든 스택은 외부 네트워크 `onprem-net`에 attach 한다.
- **볼륨**: 데이터는 명명된 볼륨 또는 `./data/<service>` 바인드 마운트로 영속화한다.
- **비밀값**: `.env`는 `.gitignore` 처리하고, `.env.example`만 커밋한다.
- **포트**: 서비스는 직접 포트 노출 대신 리버스 프록시를 통해 접근함을 원칙으로 한다.
- **이미지 태그**: `latest` 대신 고정 버전 태그를 사용해 재현성을 확보한다.

---

## 7. 미결정 사항 (Open Questions)

향후 진행하며 결정하고 `docs/decisions/`에 ADR로 기록한다.

1. **리버스 프록시**: Traefik(라벨 기반 자동 라우팅) vs Caddy(간결한 설정) — 선호?
2. **로컬 도메인**: dnsmasq 도입 vs hosts 파일 수동 관리?
3. **CI 도구**: Gitea Actions 로 충분한지, 아니면 Woodpecker/Drone 별도 고려?
4. **벡터 저장소**: Qdrant 단독 vs PostgreSQL+pgvector 통합?
5. **GPU 사용 여부**: Ollama가 GPU 가속을 쓸 환경인지 (CUDA/Metal)?
6. **백업 대상/주기**: 어떤 볼륨을 어디에 백업할지?

---

## 8. 다음 액션

이 계획이 확정되면 **Phase 0 → Phase 1** 순서로 실제 Compose 파일과 스크립트를
구현한다. 각 Phase는 독립적으로 기동/검증 가능하도록 작게 나눠 진행한다.
