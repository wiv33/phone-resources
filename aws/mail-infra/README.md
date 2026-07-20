# PhoneShin 메일 인프라 (AWS SES) — 정식 소스

휴대폰 계약서 PDF 첨부 메일을 받아 phone-api 가 처리하기 위한 AWS 인프라.
**이 디렉토리의 Terraform 이 유일한 진실 소스다** — 콘솔/CLI 수동 변경 금지, 변경은 코드로.

```
[판매점 직원] ──계약서 PDF 첨부──▶ customer@bot.phoneshin.com
     │
     ▼
SES 수신 (ap-northeast-2, TLS 필수, 스팸/바이러스 스캔)
     ├─▶ S3  phoneshin-mail-inbox-211125461385/inbox/<key>   (MIME 원문, 180일 보관)
     └─▶ SNS phoneshin-mail-received
              └─▶ SQS phoneshin-mail-ingest  (raw delivery, 14일 보존, DLQ 5회)
                       ▲
                       │ long-polling (아웃바운드만 — 온프레미스 인바운드 의존 없음)
              [phone-api SqsBridge] → 로컬 Kafka {prefix}customer.* 토픽 → 컨슈머 → OCR

발신: phone-api ──587/TLS──▶ email-smtp.ap-northeast-2.amazonaws.com
      (identity phoneshin.com, DKIM/SPF/DMARC 구성 완료. 현재 sandbox — 외부 주소 발신은 프로덕션 액세스 승인 필요)
```

## 디렉토리

| 경로 | 내용 |
|---|---|
| `terraform/` | **전체 인프라 정의** (기배포분 import 완료 — plan 은 항상 No changes 여야 정상) |
| `bootstrap-state.sh` | TF 상태 버킷/잠금테이블 생성 (1회, 완료됨) |
| `10-issue-credentials.sh` | phone-api IAM 키 발급 + k8s Secret(`phoneshin/phone-api-mail-aws`) 반영 |
| `verify.sh` | 읽기 전용 상태 점검 (identity/DNS/rule set/sandbox) |
| `legacy/` | 최초 구축용 bash (Terraform 으로 대체됨 — 실행 금지, 이력 참고용) |

## 이어받는 사람 온보딩

```bash
# 1. 전제: phoneshin AWS 계정(211125461385) 프로파일 (기본명 auto), terraform >= 1.8
aws sts get-caller-identity --profile auto     # 계정 211125461385 확인

# 2. 현재 상태 == 코드 확인 (변경 0건이어야 정상)
cd terraform && terraform init && terraform plan
#    다른 프로파일명 사용 시: terraform init -backend-config="profile=<이름>"
#                            terraform plan -var aws_profile=<이름>

# 3. 상태 점검
cd .. && ./verify.sh auto
```

## phone-api 소비자 계약 (백엔드 구현 시 이 절만 보면 됨)

- **큐**: `https://sqs.ap-northeast-2.amazonaws.com/211125461385/phoneshin-mail-ingest`
  (long-polling 20s 권장 · 처리 성공 시 DeleteMessage · visibility 60s)
- **메시지 바디** = SES 수신 알림 JSON 그대로 (raw delivery, SNS 봉투 없음):
  - `notificationType == "Received"` 확인
  - `mail.messageId` → **멱등키** (at-least-once 전달이므로 중복 처리 방지 필수)
  - `mail.source` / `mail.destination` / `mail.commonHeaders.subject`
  - `receipt.spamVerdict.status` 등 verdict 5종 — **유일하게 신뢰할 판정 소스**
  - `receipt.action.bucketName` + `receipt.action.objectKey` → S3 GetObject 로 MIME 원문
- **신뢰 규칙**: verdict(spam/virus/spf/dkim/dmarc) 전부 `PASS` + 발신자가 등록된 직원 이메일일 때만 처리.
  ⚠️ S3 원문 안의 `X-SES-*` MIME 헤더로 판정 금지 — 발신자가 위조 가능(중복 헤더). SNS/SQS 의 receipt 만 신뢰.
- **자격증명**: k8s Secret `phoneshin/phone-api-mail-aws` (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_REGION`)
  — IAM 사용자 `phone-api-mail-consumer`, 권한은 이 큐 소비 + `inbox/*` 읽기뿐
- **Kafka 토픽 네이밍**: `{variables.kafka.topic.prefix}customer.…` — 도메인 네이밍 통일 방침 (2026-07-20 결정)

## 런북

| 상황 | 절차 |
|---|---|
| 자격증명 발급/교체 | `./10-issue-credentials.sh auto` (VPN 필요 — kubectl 사전검사 내장). 교체 후 옛 키 삭제 |
| 원문 보관기간 변경 | `terraform apply -var mail_retention_days=<N>` |
| DLQ 적체 | `aws sqs receive-message --queue-url <dlq-url>` 로 원인 확인 → 컨슈머 수정 후 SQS 콘솔 redrive |
| DLQ 알람 켜기 | `terraform apply -var alarm_email=<주소>` → 확인 메일 승인 |
| 발신 sandbox 해제 | SES 콘솔 → Account dashboard → Request production access (수동 1회) |
| 수신 E2E 테스트 | 아무 메일 → `test@bot.phoneshin.com` → `aws s3 ls s3://phoneshin-mail-inbox-211125461385/inbox/` + SQS 메시지 확인 |
| DKIM 토큰 재발급됨 | (identity 재생성 시에만) `terraform/main.tf` 의 `locals.dkim_tokens` 갱신 |

## 결정 로그

- **자체 메일서버 불가** (2026-07-18): 사무실 KT 동적 IP + PTR 미설정 → 자체 발신은 스팸행 확정. SES 채택.
- **수신은 서브도메인 `bot.`**: apex MX 를 비워둬 추후 직원용 메일(Workspace 등)과 충돌 방지.
- **SQS 경유** (2026-07-20): 온프레미스가 인바운드 웹훅 없이 아웃바운드 폴링만으로 소비 + AWS 측 14일 버퍼 + SNS verdict 보존. AWS→로컬 Kafka 직접 produce 는 불가(네이티브 통합 없음 + advertised listener 가 클러스터 내부 DNS — 실측).
- **TLS Require / verdict 는 SNS 만 신뢰 / 180일 수명주기**: 멀티에이전트 보안 리뷰 확정 사항.
- **DMARC rua=`dmarc@bot.phoneshin.com`**: 리포트도 같은 인박스로 수신. 발신량 증가 시 `p=none`→`quarantine` 상향 검토.

## 남은 일 (2026-07-20 기준)

1. ~~Terraform 코드화~~ ✅ (18 import + 6 add, plan 무변경 확인)
2. **자격증명 → k8s Secret**: VPN 연결 후 `./10-issue-credentials.sh auto`
3. **발신 sandbox 해제** (외부 주소로 보낼 필요가 생길 때)
4. **phone-api 백엔드**: `BACKEND-HANDOFF.md` 참조 (SqsBridge → Kafka → MIME 파싱 → ContractOcrPort 재사용 → mail_ingest 검토대기)
5. FE 검토 화면 (mail_ingest 대기목록 → 확인 → Customer 확정)
