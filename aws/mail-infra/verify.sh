#!/usr/bin/env bash
# =============================================================================
# verify - 메일 인프라 상태 점검 (읽기 전용)
# 사용법: ./verify.sh <aws-profile>
# =============================================================================
set -uo pipefail

PROFILE="${1:?사용법: $0 <aws-profile>}"
DOMAIN="phoneshin.com"
RECV_DOMAIN="bot.phoneshin.com"
MAILFROM_DOMAIN="mail.phoneshin.com"
REGION="ap-northeast-2"
RULE_SET="phoneshin-inbound"

AWS="aws --profile ${PROFILE} --region ${REGION}"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "=== 1. SES identity (발신) ==="
DKIM=$($AWS sesv2 get-email-identity --email-identity "${DOMAIN}" --query "DkimAttributes.Status" --output text 2>/dev/null)
[[ "${DKIM}" == "SUCCESS" ]] && ok "DKIM 검증: SUCCESS" || bad "DKIM 검증: ${DKIM:-없음}"
MF=$($AWS sesv2 get-email-identity --email-identity "${DOMAIN}" --query "MailFromAttributes.MailFromDomainStatus" --output text 2>/dev/null)
[[ "${MF}" == "SUCCESS" ]] && ok "MAIL FROM(${MAILFROM_DOMAIN}): SUCCESS" || bad "MAIL FROM: ${MF:-없음}"

echo "=== 2. DNS (공개 리졸버 기준) ==="
MX_RECV=$(dig +short MX "${RECV_DOMAIN}" | head -1)
[[ "${MX_RECV}" == *"inbound-smtp.${REGION}.amazonaws.com"* ]] && ok "수신 MX: ${MX_RECV}" || bad "수신 MX 미전파: '${MX_RECV}'"
MX_MF=$(dig +short MX "${MAILFROM_DOMAIN}" | head -1)
[[ "${MX_MF}" == *"feedback-smtp.${REGION}.amazonses.com"* ]] && ok "MAIL FROM MX: ${MX_MF}" || bad "MAIL FROM MX 미전파: '${MX_MF}'"
SPF=$(dig +short TXT "${MAILFROM_DOMAIN}" | head -1)
[[ "${SPF}" == *"amazonses.com"* ]] && ok "SPF: ${SPF}" || bad "SPF 미전파: '${SPF}'"
DMARC=$(dig +short TXT "_dmarc.${DOMAIN}" | head -1)
[[ "${DMARC}" == *"DMARC1"* ]] && ok "DMARC: ${DMARC}" || bad "DMARC 미전파: '${DMARC}'"

echo "=== 3. SES 수신 파이프라인 ==="
ACTIVE=$($AWS ses describe-active-receipt-rule-set --query "Metadata.Name" --output text 2>/dev/null)
[[ "${ACTIVE}" == "${RULE_SET}" ]] && ok "active rule set: ${ACTIVE}" || bad "active rule set: ${ACTIVE:-없음} (기대: ${RULE_SET})"
ACCOUNT_ID=$($AWS sts get-caller-identity --query Account --output text 2>/dev/null)
BUCKET="phoneshin-mail-inbox-${ACCOUNT_ID}"
$AWS s3api head-bucket --bucket "${BUCKET}" 2>/dev/null && ok "S3 버킷: ${BUCKET}" || bad "S3 버킷 없음: ${BUCKET}"

echo "=== 4. 발신 상태 (sandbox 여부) ==="
SANDBOX=$($AWS sesv2 get-account --query "ProductionAccessEnabled" --output text 2>/dev/null)
if [[ "${SANDBOX}" == "True" ]]; then ok "프로덕션 액세스: 활성"; else
  echo "  ⚠️  sandbox 상태 — 검증된 주소로만 발신 가능 (수신은 제한 없음)."
  echo "      해제: SES 콘솔 > Account dashboard > Request production access"
fi

echo ""
echo "결과: ${PASS} pass / ${FAIL} fail"
echo "수신 최종 테스트: 외부 메일 -> test@${RECV_DOMAIN} 발송 후 s3://${BUCKET}/inbox/ 확인"
[[ ${FAIL} -eq 0 ]]
