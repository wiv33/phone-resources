# PhoneShin PostgreSQL (bitnami helm chart)

GitOps 외부에서 **helm 으로 직접 관리** (ArgoCD app X). `database` 네임스페이스에 standalone 으로 떠 있다.

## 구성 요소

| 파일 | 역할 |
|---|---|
| `main.tf` | istio VirtualService — 외부 진입 5432 포트 routing |
| `values.yaml` | bitnami chart 의 nano preset override (resources 명시) |

## 적용된 chart

- chart: `bitnami/postgresql` 15.2.8 (PG 16.2.0)
- release name: `postgresql`
- namespace: `database`
- 최초 install: 2024-05-19

## 운영 변경 이력

| 일자 | 변경 | 이유 |
|---|---|---|
| 2026-05-12 | `primary.resourcesPreset=none` + 명시 resources (memory 192Mi→2Gi, cpu 150m→1500m) | OOMKilled (exitCode 137) 4h 사이 3회 재기동. 매일 subsidy/wired_plan UPSERT 부담. |

## resources 변경 적용 명령

```bash
KUBECONFIG=~/.kube/shin_config helm repo add bitnami https://charts.bitnami.com/bitnami
KUBECONFIG=~/.kube/shin_config helm repo update bitnami

KUBECONFIG=~/.kube/shin_config helm upgrade postgresql bitnami/postgresql \
  -n database \
  --version 15.2.8 \
  --reuse-values \
  -f values.yaml
```

`--reuse-values` 필수 — values.yaml 은 patch 만 담고 있어서 기본 설정 (auth.password 등) 은 helm 의 release 에서 가져와야 한다.

## 검증

```bash
# StatefulSet 의 resources 확인
KUBECONFIG=~/.kube/shin_config kubectl get sts postgresql -n database \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="postgresql")].resources}' | python3 -m json.tool

# pod Ready
KUBECONFIG=~/.kube/shin_config kubectl get pod postgresql-0 -n database

# 외부 진입 (VirtualService 5432 → 55432 publish 가 별도)
PGPASSWORD='<pwd>' psql -h phoneshin.com -p 55432 -U shin -d shin -c "SELECT NOW();"
```

## 알려진 위험

- harbor / keycloak / dabeeo 의 PG 도 같은 nano preset 일 가능성 — 동일 OOM 위험. 별도 점검 권장.
- values.yaml 이 chart 의 일부 설정만 담고 있다. `helm install` 신규 시 `--reuse-values` 가 동작 안 함 — release 가 이미 있을 때만 사용. 신규 install 은 별도 secret/auth 설정 필요.
