# playwright-paginator

self-hosted Firecrawl 가 actions(click/eval) 미지원이라 SPA 페이지네이션 처리가 불가능 — 본 사이드카가 그 빈자리 채움.

## 빌드 + 배포 (one-time)

```bash
cd phone-resources/firecrawl/paginator

# 1) Harbor 로그인
docker login registry-harbor.phoneshin.com

# 2) build (linux/amd64 — backbone-worker 기준)
docker buildx build \
  --platform=linux/amd64 \
  --tag registry-harbor.phoneshin.com/phoneshin/playwright-paginator:latest \
  --push .

# 3) ArgoCD sync (이미 phone-resources 의 firecrawl/base 에 등록됨)
kubectl -n argocd patch app firecrawl --type merge -p '{"operation":{"sync":{}}}'

# 4) 확인
kubectl get pods -n firecrawl -l component=paginator
```

## API

### POST /paginate

```json
{
  "url": "https://shop.tworld.co.kr/notice?...",
  "paginationJs": "goPage({n})",
  "maxPages": 5,
  "waitMs": 4000,
  "initialWaitMs": 4000
}
```

응답:
```json
{
  "success": true,
  "url": "...",
  "pages": [{"n": 1, "length": 12300}, {"n": 2, "length": 11800}, ...],
  "aggregateText": "\n--- PAGE 1 ---\n...\n--- PAGE 2 ---\n...",
  "durationMs": 23456
}
```

phone-crawl 의 carrier 어댑터가 본 응답의 `aggregateText` 를 LLM 추출 prompt 와 함께 HF Router 로 전달.

### GET /healthz

200 OK if browser pool initialized.
