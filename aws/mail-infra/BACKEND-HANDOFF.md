# phone-api 백엔드 구현 핸드오프 — 계약서 메일 인제스트

> 선행: 이 디렉토리의 AWS 인프라 (완료, `README.md` 참조). 이 문서는 phone-api 저장소 정찰
> (2026-07-20, 파일 단위 실측) 기반으로 작성됨 — 아래 경로·패턴은 전부 실제 코드에서 확인한 것.

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

### 처리 흐름 상세 (MailIngestHandler)
1. `ses_message_id` 존재 → 즉시 성공 반환 (멱등).
2. verdict 5종 중 하나라도 != PASS → status `REJECTED` (reject_reason 에 어떤 verdict 인지).
3. `mail.source` 를 `mail_sender`(enabled) 에서 조회 실패 → `REJECTED` (unknown sender). 성공 → staff_id + `store_staff(is_default=true)` 로 store_id.
4. 수신 주소 localpart != `customer` → `REJECTED` (다른 자동화 주소를 위한 여지).
5. S3 GetObject → MIME 파싱 → PDF 파트 0건이면 `REJECTED`; 여러 건이면 각각 OCR (mail_ingest 는 메일 단위 1행, ocr_fields 는 첨부별 배열도 허용 — 구현 시 결정).
6. ContractOcrPort → 성공 `EXTRACTED` / 실패 `FAILED` (error 기록). Claude 호출엔 `.timeout()`.

### 웹 API (FE 검토 화면용)
- `MailIngestRouter` (@WebAdapter): `GET /v1/mail-ingest?status=EXTRACTED` 목록 / `GET /v1/mail-ingest/{id}` 상세(+원문 PDF presign 은 mail 버킷용 어댑터에 presign 추가 시) / `PATCH /v1/mail-ingest/{id}/confirm {customerId}`.
- Customer 생성은 **기존 `POST /v1/customer`** 를 FE 가 그대로 사용. OCR 이 못 채우는 **필수** 필드: `joinInfo.salesStoreId`(store_id 로 프리필 가능), `joinInfo.agencyId`, `wirelessInfo.rebateNet` — 사람이 채워야 하는 이유이자 자동생성 금지의 근거 (CustomerValidator.kt 실측).

### 테스트 (기존 스타일)
- 라우터: `WiredPlanRouterTest.kt` 스타일 — Spring 컨텍스트 없이 `WebTestClient.bindToRouterFunction`, mockito-kotlin, 한국어 백틱 테스트명.
- 핸들러: `CreditAlertHandlerTest.kt` 스타일 — 포트 mock + `StepVerifier`.
- **SES 알림 JSON 직렬화 계약 테스트 필수** (`CreditAlertEventSerializationTest` 선례): 실제 SQS 메시지를 fixture 로 고정 → KotlinModule 사고 재발 방지. fixture 는 이 인프라의 E2E 테스트에서 확보 가능 (README 런북).

### 배포 (phone-resources)
- `phone-api/overlay/prod/deploy.yaml` env 추가: `AWS_MAIL_ACCESS_KEY`/`AWS_MAIL_SECRET_KEY` 는 `secretKeyRef: phone-api-mail-aws` (`PHONE_API_INTERNAL_AUTH_TOKEN` 의 secretKeyRef 선례), `AWS_MAIL_SQS_QUEUE_URL`/`AWS_MAIL_S3_BUCKET`/`MAIL_INGEST_BRIDGE_ENABLED=true` 는 literal value (MESSAGING_* 선례). Secret 은 `10-issue-credentials.sh` 가 생성 (VPN 필요, 실행 대기 중).
- 값: README.md 의 "phone-api 소비자 계약" 절 참조.

### 마무리 체크리스트
- [ ] `docs/feature-impact-map.md` 갱신 (라우터/마이그레이션 추가 시 필수 — 루트 CLAUDE.md 규칙)
- [ ] `./gradlew test` (CI 는 테스트를 안 돌림 — bootJar 만. 가드는 로컬 테스트뿐)
- [ ] mail_sender 시드: 최초 허용 직원 이메일 INSERT (관리 UI 는 후속)
- [ ] prod `CLAUDE_API_KEY` 설정 확인
