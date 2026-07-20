# phone-api 백엔드 구현 핸드오프 — 계약서 메일 인제스트

> 선행: 이 디렉토리의 AWS 인프라 (완료, `README.md` 참조).
> **구현 완료(2026-07-20)** — phone-api `mail/` 패키지로 구현·테스트·적대적 리뷰(26 에이전트)·수정까지 마침.
> 아래는 설계 근거와 배포 시 필요한 사항. 코드는 phone-api repo `src/main/kotlin/.../mail/`.

## 구현 상태 (2026-07-20)

- `mail/` 패키지: 도메인/포트/핸들러/파서/SQS브리지/Kafka컨슈머/웹라우터/영속성 — 완료
- 테스트 21개 통과 (직렬화 계약 5 + 핸들러 파이프라인 10 + 라우터 6)
- 멀티에이전트 리뷰 확정 결함 전부 반영: **테넌트 격리**(회사 스코프 조회), **SPF 게이트**(DKIM 단독 불충분),
  **offset earliest**(첫 배포 백로그 유실 방지), **성공 시에만 ack**(종료 중 in-flight 유실 방지),
  **오류 분류**(일시장애는 재시도, poison만 skip), **S3 버킷 검증**, **조건부 confirm**(경쟁 방지),
  **인라인 이미지 제외**·다중첨부 거절·필드 절단·FAILED 재처리.
- ⚠️ **배포 필수 조건** — `MAIL_INGEST_BRIDGE_ENABLED`·`MAIL_INGEST_CONSUMER_ENABLED` **둘 다 기본 false**
  (환경 공용 큐/토픽이라 비-prod 파드가 운영 메일을 가로채는 것 방지). **prod 오버레이에서 둘 다 true 로 설정해야
  기능이 동작**한다. 아래 "배포" 절 참조.

## 목표

판매점 직원이 `customer@bot.phoneshin.com` 으로 보낸 **휴대폰 계약서 PDF 첨부 메일**을
읽어 OCR 추출 → 검토대기 저장 → (FE 에서 사람이 확인 후) 기존 고객등록 API 로 Customer 생성.

```
SQS phoneshin-mail-ingest ──(1) MailSqsBridge──▶ Kafka local.api.customer_contract_mail
                                                        │
                                (2) CustomerContractMailConsumer (@MessagingAdapter)
                                                        │
        (3) MailIngestHandler: 멱등 → verdict → allowlist → S3 원문 → PDF 추출 → ContractOcrPort → mail_ingest 저장
                                                        │
        (4) MailIngestRouter: 검토대기 목록/상세 → FE → 기존 POST /v1/customer → confirm
```

## 결정된 것 (변경하지 말 것)

| 항목 | 값 | 근거 |
|---|---|---|
| Kafka 토픽 | `{prefix}customer_contract_mail` | 사용자 지시: 토픽에 customer 포함. 기존 suffix 스타일(`customer_event`, `credit_alert`) 준수 |
| 신뢰 판정 | SQS 메시지의 `receipt.*Verdict` 5종 전부 PASS | S3 원문의 X-SES-* 헤더는 발신자 위조 가능 (보안 리뷰 확정) |
| 멱등키 | `mail.messageId` (SES) → `mail_ingest.ses_message_id` UNIQUE | SQS at-least-once + Kafka 재전달 대비 |
| 자동 Customer 생성 금지 | OCR 결과는 검토대기까지만 | 메일은 공개 입력면 + OCR 필수필드 부족(아래) |
| 발신자 매칭 | 신규 `mail_sender` 테이블 | **staff 테이블에 email 컬럼이 없음** (실측: entity/Staff.kt — tel 뿐) |

## phone-api 실측 사실 (구현 시 그대로 따를 패턴)

### Kafka (기존 패턴 복제 대상: `credit/adapter/in/kafka/CreditAlertConsumer.kt`)
- 토픽 = `@Value("${variables.kafka.topic.prefix}")` + suffix. **prefix 는 전 프로파일 동일 `local.api.`** (prod 포함 — 기존 quirk, 건드리지 말 것).
- `NewTopic` 빈은 `config/KafkaConfiguration.java` 에 추가 (기존: sms, customer_event(3파티션), credit_alert).
- 컨슈머 골격: `@MessagingAdapter` + `@EventListener(ApplicationReadyEvent)` 로 시작, 공유 `ReceiverOptions` 빈에 `.consumerProperty(GROUP_ID_CONFIG, "phone-api-customer-contract-mail")` + `.subscription(...)` → `KafkaReceiver.create(...).receive().concatMap { processRecord(it).doFinally { it.receiverOffset().acknowledge() } }.retryWhen(Retry.backoff(Long.MAX_VALUE, 5s).maxBackoff(1m))` → `@PreDestroy dispose`.
- poison 메시지: `onErrorResume { log.error(...); Mono.empty() }` — 스트림 죽이지 않고 skip.
- **ObjectMapper 는 수동 생성 + `KotlinModule` + `JavaTimeModule` + `FAIL_ON_UNKNOWN_PROPERTIES=false` 필수** — KotlinModule 누락 시 data class 전량 silent skip (2026-06-12 실사고, CreditAlertConsumer.kt 43-45줄 주석).
- enable 플래그 패턴: `@Value("\${mail.ingest.consumer-enabled:true}")` (기존 `messaging.alert.consumer-enabled` 모방).

### SQS 브리지 (신규 — 유일하게 선례 없는 부분)
- 의존성: `implementation("software.amazon.awssdk:sqs")` — **기존 BOM 2.27.21 이 버전 관리** (build.gradle.kts:57).
- `SqsAsyncClient` + long-poll(20s) 루프 → 수신 메시지 body(=SES 알림 JSON 그대로, raw delivery)를 Kafka 로 재발행(key=`mail.messageId`) → 발행 성공 시 DeleteMessage. 실패 시 삭제하지 않음(visibility 60s 후 재전달, 5회 후 DLQ).
- **플래그 `mail.ingest.bridge-enabled` 기본 false, prod 만 true** — 로컬 개발자가 SQS 를 경쟁 소비해 prod 메시지를 가로채는 사고 방지. (Kafka 쪽은 컨슈머 그룹이 보호하지만 SQS 는 큐 하나뿐.)
- phone-api 다중 replica 는 문제 없음 (SQS 는 competing-consumer 안전, ShedLock 불필요).

### S3 (메일 원문 읽기)
- 기존 `S3Adapter` 는 presign URL 생성 전용이라 용도가 다름. **재사용하지 말고** 최소권한 메일 전용 자격증명(`phone-api-mail-consumer`)을 쓰는 `aws.mail.*` 네임스페이스 신규 어댑터:
  ```yaml
  aws:
    mail:                                # application.yml 에 추가
      access-key: ${AWS_MAIL_ACCESS_KEY:}
      secret-key: ${AWS_MAIL_SECRET_KEY:}
      region: ${AWS_MAIL_REGION:ap-northeast-2}
      sqs-queue-url: ${AWS_MAIL_SQS_QUEUE_URL:}
      s3-bucket: ${AWS_MAIL_S3_BUCKET:}
  ```
- `MailObjectPort` (out port) + `MailObjectS3Adapter`: `S3AsyncClient.getObject` 로 바이트 취득 (presign 불필요 — 서버 내부 처리).

### MIME 파싱
- **레포에 메일 파서 전무** (실측: jakarta.mail/angus/mime4j 0건). 추가: `implementation("org.springframework.boot:spring-boot-starter-mail")` (Boot 3.3.4 가 angus-mail 버전 관리) → `MimeMessage(null, inputStream)` 로 파싱, multipart 순회, `application/pdf` 파트 추출.
- 첨부 제한: 기존 OcrHandler 와 동일 (20MB, PDF/JPEG/PNG/WebP). 블로킹 파싱은 `Schedulers.boundedElastic()` 로 감쌀 것 (OcrHandler 패턴).

### OCR (그대로 재사용 — 수정 불필요)
- `ContractOcrPort.extractContractData(base64Data: String, mediaType: String): Mono<ContractOcrResult>`
- `ContractFields`: name, activationNumber, birthDate, telecom(SKT/KT/LGU), previousTelecom, activationType(MNP/기변/신규), modelName, serialNumber, activationRatePlanName, contractType(공시/선약), phoneReleasePrice, publicSupportAmount, installmentMonths, policyInfo(현금/할부), activationDateTime.
- 구현체 `ClaudeVisionAdapter` 는 PDF 를 document 블록으로 처리(스캔본 OK). ⚠️ **타임아웃 미설정** — 컨슈머 경로에서는 `.timeout(Duration.ofMinutes(2))` 를 걸어 스트림 보호 권장.
- ⚠️ `CLAUDE_API_KEY` 가 git 추적 매니페스트 어디에도 없음 (빈 값이면 OCR 이 "key not configured" 실패) — **prod 파드에 실제로 설정돼 있는지 배포 전 확인**: `kubectl -n phoneshin exec deploy/<phone-api> -- env | grep CLAUDE`.

### DB 마이그레이션
- **Flyway 아님** — `src/main/resources/db/migration/` 에 V파일 두고 **psql 로 수동 적용** (`docs/INITIAL_SETUP.md`, "V20 psql 직접 적용" 패턴). 최신 = **V23** → 이 작업은 **V24**.
- 스타일: `CREATE TABLE IF NOT EXISTS`, 로그성 테이블은 `BIGSERIAL PK`, `TIMESTAMP NOT NULL DEFAULT NOW()`, 한국어 COMMENT, `idx_<table>_<purpose>`, 마지막에 `ALTER TABLE ... OWNER TO shin;`.

#### V24__mail_ingest.sql 초안
```sql
-- 계약서 메일 발신 허용 직원 (staff 에 email 컬럼이 없어 별도 매핑)
CREATE TABLE IF NOT EXISTS mail_sender (
    id BIGSERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    staff_id BIGINT NOT NULL REFERENCES staff(id),
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 메일 인제스트 이력/검토대기 (멱등키 = ses_message_id)
CREATE TABLE IF NOT EXISTS mail_ingest (
    id BIGSERIAL PRIMARY KEY,
    ses_message_id VARCHAR(255) NOT NULL UNIQUE,
    from_email VARCHAR(255) NOT NULL,
    recipient VARCHAR(255) NOT NULL,
    subject VARCHAR(500),
    s3_bucket VARCHAR(255) NOT NULL,
    s3_key VARCHAR(500) NOT NULL,
    verdict_summary VARCHAR(100) NOT NULL,        -- 예: PASS 또는 spam=FAIL
    status VARCHAR(30) NOT NULL,                  -- RECEIVED/REJECTED/EXTRACTED/FAILED/CONFIRMED
    reject_reason VARCHAR(255),
    staff_id BIGINT,                              -- mail_sender 매칭 결과
    store_id BIGINT,                              -- store_staff(is_default=true) 로 해석
    ocr_confidence VARCHAR(10),
    ocr_fields JSONB,                             -- ContractFields 직렬화
    customer_id BIGINT,                           -- confirm 후 연결
    error TEXT,
    received_at TIMESTAMP NOT NULL DEFAULT NOW(),
    processed_at TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_mail_ingest_status ON mail_ingest(status, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_mail_ingest_store ON mail_ingest(store_id, received_at DESC);

ALTER TABLE mail_sender OWNER TO shin;
ALTER TABLE mail_ingest OWNER TO shin;
```

### 처리 흐름 상세 (MailIngestHandler — 구현된 순서)
1. `ses_message_id` 존재 → `FAILED` 면 재처리(같은 id UPDATE, 일시장애 복구), 그 외 상태는 멱등 반환.
2. **verdict** — spam/virus/**spf** != PASS → `REJECTED`. DKIM 은 게이트 아님(서명 도메인이 봉투 발신자와 달라 단독으론 신원 불충분; allowlist 를 `mail.source` 로 매칭하므로 SPF 필수).
3. **S3 버킷 검증** — `action.bucketName` != `aws.mail.s3-bucket` → `REJECTED` (위조 Kafka 메시지의 임의 버킷 읽기 차단).
4. **수신 주소** — 로컬파트(`customer`) **AND** 도메인(`bot.phoneshin.com`) 모두 일치해야 통과.
5. **발신자 allowlist** — `mail.source` 를 `mail_sender`(enabled)에서 조회. 실패 → `REJECTED`. 성공 → staff→**company_id**(테넌트 키)+store_id(`store_staff.is_default`).
6. **S3 원문** — HeadObject 크기 캡(45MB) → GetObject → MIME 파싱. 인라인 이미지 제외. PDF 우선(동봉 이미지 무시), PDF 없으면 단일 이미지. **PDF·이미지 각각 2개 이상 → `REJECTED`**(한 통에 한 계약), 20MB 초과 → `REJECTED`.
7. **OCR** — `ContractOcrPort`(`.timeout()`) → 성공 `EXTRACTED`(confidence 는 {high,medium,low} 정규화) / 실패 `FAILED`.
- 실패/거절 어느 단계든 `mail_ingest` 행은 남는다. reject_reason 은 255자 절단.

### 웹 API (FE 검토 화면용) — **모두 회사 스코프(PHONE-COMPANY-ID)**
- `MailIngestRouter` (@WebAdapter): `GET /v1/mail-ingest?status=EXTRACTED` 목록 / `GET /v1/mail-ingest/{id}` 상세 / `PATCH /v1/mail-ingest/{id}/confirm {customerId}`.
- **테넌트 격리**: 모든 조회·확정이 호출자 회사로 필터됨(타 회사 계약서 PII 차단). confirm 은 `EXTRACTED AND company 일치`일 때만 조건부 UPDATE(동시 확정 경쟁 안전), 불일치=404/상태오류=409.
- Customer 생성은 **기존 `POST /v1/customer`** 를 FE 가 그대로 사용. OCR 이 못 채우는 **필수** 필드: `joinInfo.salesStoreId`(store_id 로 프리필 가능), `joinInfo.agencyId`, `wirelessInfo.rebateNet` — 사람이 채워야 하는 이유이자 자동생성 금지의 근거 (CustomerValidator.kt 실측).

### 테스트 (기존 스타일)
- 라우터: `WiredPlanRouterTest.kt` 스타일 — Spring 컨텍스트 없이 `WebTestClient.bindToRouterFunction`, mockito-kotlin, 한국어 백틱 테스트명.
- 핸들러: `CreditAlertHandlerTest.kt` 스타일 — 포트 mock + `StepVerifier`.
- **SES 알림 JSON 직렬화 계약 테스트 필수** (`CreditAlertEventSerializationTest` 선례): 실제 SQS 메시지를 fixture 로 고정 → KotlinModule 사고 재발 방지. fixture 는 이 인프라의 E2E 테스트에서 확보 가능 (README 런북).

### 배포 (phone-resources) — prod 오버레이 env 추가 (기능 활성화의 유일한 스위치)
`phone-api/overlay/prod/deploy.yaml` 의 env 에 아래를 추가한다. **Secret(`phone-api-mail-aws`) 을 먼저 만든 뒤**
(`10-issue-credentials.sh`, VPN 필요) secretKeyRef 를 넣어야 파드가 뜬다 — 없는 Secret 참조는 기동 실패.

```yaml
# 활성화 스위치 (둘 다 없으면 기능 off — 기본값이 false)
- name: MAIL_INGEST_BRIDGE_ENABLED
  value: "true"
- name: MAIL_INGEST_CONSUMER_ENABLED
  value: "true"
# 비-secret 설정 (MESSAGING_* 처럼 literal)
- name: AWS_MAIL_SQS_QUEUE_URL
  value: "https://sqs.ap-northeast-2.amazonaws.com/211125461385/phoneshin-mail-ingest"
- name: AWS_MAIL_S3_BUCKET
  value: "phoneshin-mail-inbox-211125461385"
- name: AWS_MAIL_REGION
  value: "ap-northeast-2"
# 자격증명 (PHONE_API_INTERNAL_AUTH_TOKEN 의 secretKeyRef 선례)
- name: AWS_MAIL_ACCESS_KEY
  valueFrom: { secretKeyRef: { name: phone-api-mail-aws, key: AWS_ACCESS_KEY_ID } }
- name: AWS_MAIL_SECRET_KEY
  valueFrom: { secretKeyRef: { name: phone-api-mail-aws, key: AWS_SECRET_ACCESS_KEY } }
```
- 그 외 튜닝(선택): `MAIL_INGEST_RECIPIENT_DOMAIN`(기본 bot.phoneshin.com), `MAIL_INGEST_OCR_TIMEOUT_SECONDS`(120).
- **`CLAUDE_API_KEY` 확인** — OCR(ContractOcrPort)이 이 키로 동작. prod 파드에 실제 설정돼 있는지 배포 전 확인.

### 마무리 체크리스트
- [ ] `docs/feature-impact-map.md` 갱신 (라우터/마이그레이션 추가 시 필수 — 루트 CLAUDE.md 규칙)
- [ ] `./gradlew test` (CI 는 테스트를 안 돌림 — bootJar 만. 가드는 로컬 테스트뿐)
- [ ] mail_sender 시드: 최초 허용 직원 이메일 INSERT (관리 UI 는 후속)
- [ ] prod `CLAUDE_API_KEY` 설정 확인
