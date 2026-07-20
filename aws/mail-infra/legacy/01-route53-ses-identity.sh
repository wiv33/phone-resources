#!/usr/bin/env bash
# =============================================================================
# 01 - SES 도메인 identity(발신 DKIM/MAIL FROM) 생성 + Route53 레코드 등록
#
# 생성하는 것:
#   - SES v2 email identity: phoneshin.com (Easy DKIM, RSA 2048)
#   - custom MAIL FROM domain: mail.phoneshin.com
#   - Route53 레코드 (UPSERT):
#       * DKIM CNAME x3      <token>._domainkey.phoneshin.com -> <token>.dkim.amazonses.com
#       * MAIL FROM MX       mail.phoneshin.com -> 10 feedback-smtp.ap-northeast-2.amazonses.com
#       * MAIL FROM SPF TXT  mail.phoneshin.com -> "v=spf1 include:amazonses.com ~all"
#       * DMARC TXT          _dmarc.phoneshin.com -> p=none, rua=dmarc@bot.phoneshin.com
#       * 수신 MX            bot.phoneshin.com -> 10 inbound-smtp.ap-northeast-2.amazonaws.com
#
# 사용법:  ./01-route53-ses-identity.sh <aws-profile>
#   (phoneshin.com hosted zone 이 있는 계정의 프로파일이어야 함 — 스크립트가 검증)
# 멱등:    재실행 안전 (identity 존재 시 재사용, 레코드는 UPSERT)
# 안전장치: 값이 다른 기존 레코드가 있으면 중단. 덮어쓰려면 FORCE=1 로 실행.
# =============================================================================
set -euo pipefail
export AWS_PAGER=""

PROFILE="${1:?사용법: $0 <aws-profile>   (phoneshin.com 존이 있는 계정 프로파일)}"
DOMAIN="phoneshin.com"
RECV_DOMAIN="bot.phoneshin.com"        # 자동화 수신 전용 서브도메인 (변경 시 02번 스크립트와 함께)
MAILFROM_DOMAIN="mail.phoneshin.com"   # SES custom MAIL FROM (발신 봉투 도메인)
REGION="ap-northeast-2"
DMARC_RUA="dmarc@${RECV_DOMAIN}"       # DMARC 리포트도 수신 S3 인박스로 흘러들어옴
TTL=600

AWS="aws --profile ${PROFILE} --region ${REGION}"

echo "==> [0/5] 계정/존 검증"
ACCOUNT_ID=$($AWS sts get-caller-identity --query Account --output text)
echo "    계정: ${ACCOUNT_ID}"

ZONE_ID=$($AWS route53 list-hosted-zones-by-name --dns-name "${DOMAIN}." \
  --query "HostedZones[?Name=='${DOMAIN}.' && Config.PrivateZone==\`false\`]|[0].Id" --output text)
if [[ -z "${ZONE_ID}" || "${ZONE_ID}" == "None" ]]; then
  echo "!! 이 프로파일(${PROFILE}, 계정 ${ACCOUNT_ID})에 ${DOMAIN} public hosted zone 이 없습니다." >&2
  echo "   phoneshin.com 을 보유한 계정의 프로파일로 다시 실행하세요." >&2
  exit 1
fi
ZONE_ID="${ZONE_ID##*/}"   # /hostedzone/XXXX -> XXXX
echo "    hosted zone: ${ZONE_ID}"

echo "==> [1/5] SES email identity 생성/조회: ${DOMAIN}"
if $AWS sesv2 get-email-identity --email-identity "${DOMAIN}" >/dev/null 2>&1; then
  echo "    이미 존재 — 재사용"
else
  $AWS sesv2 create-email-identity --email-identity "${DOMAIN}" \
    --dkim-signing-attributes "NextSigningKeyLength=RSA_2048_BIT" >/dev/null
  echo "    생성됨"
fi

get_tokens() {
  $AWS sesv2 get-email-identity --email-identity "${DOMAIN}" \
    --query "DkimAttributes.Tokens" --output text 2>/dev/null || true
}
TOKENS=$(get_tokens)
if [[ -z "${TOKENS}" || "${TOKENS}" == "None" ]]; then
  echo "    기존 identity 에 Easy DKIM 미설정 — 활성화"
  $AWS sesv2 put-email-identity-dkim-signing-attributes \
    --email-identity "${DOMAIN}" \
    --signing-attributes-origin AWS_SES \
    --signing-attributes "NextSigningKeyLength=RSA_2048_BIT" >/dev/null
  for i in $(seq 1 6); do
    TOKENS=$(get_tokens)
    [[ -n "${TOKENS}" && "${TOKENS}" != "None" ]] && break
    sleep 5
  done
fi
read -r T1 T2 T3 <<< "${TOKENS}"
if [[ -z "${T1:-}" || -z "${T2:-}" || -z "${T3:-}" ]]; then
  echo "!! DKIM 토큰 3개를 얻지 못했습니다: '${TOKENS}'" >&2
  echo "   SES 콘솔에서 ${DOMAIN} identity 의 DKIM 설정을 확인하세요." >&2
  exit 1
fi
echo "    DKIM tokens: ${T1} ${T2} ${T3}"

echo "==> [2/5] custom MAIL FROM 설정: ${MAILFROM_DOMAIN}"
$AWS sesv2 put-email-identity-mail-from-attributes \
  --email-identity "${DOMAIN}" \
  --mail-from-domain "${MAILFROM_DOMAIN}" \
  --behavior-on-mx-failure USE_DEFAULT_VALUE

echo "==> [3/5] 기존 레코드 충돌 검사"
# name|type|expected-value — 기존 값이 있고 기대값과 다르면 중단(FORCE=1 시 덮어씀)
EXPECT=(
  "${T1}._domainkey.${DOMAIN}.|CNAME|${T1}.dkim.amazonses.com"
  "${T2}._domainkey.${DOMAIN}.|CNAME|${T2}.dkim.amazonses.com"
  "${T3}._domainkey.${DOMAIN}.|CNAME|${T3}.dkim.amazonses.com"
  "${MAILFROM_DOMAIN}.|MX|10 feedback-smtp.${REGION}.amazonses.com"
  "${MAILFROM_DOMAIN}.|TXT|\"v=spf1 include:amazonses.com ~all\""
  "_dmarc.${DOMAIN}.|TXT|\"v=DMARC1; p=none; rua=mailto:${DMARC_RUA}\""
  "${RECV_DOMAIN}.|MX|10 inbound-smtp.${REGION}.amazonaws.com"
)
CONFLICTS=0
for e in "${EXPECT[@]}"; do
  IFS='|' read -r NAME TYPE WANT <<< "${e}"
  GOT=$($AWS route53 list-resource-record-sets --hosted-zone-id "${ZONE_ID}" \
    --start-record-name "${NAME}" --start-record-type "${TYPE}" --max-items 1 \
    --query "ResourceRecordSets[?Name=='${NAME}' && Type=='${TYPE}']|[0].ResourceRecords[0].Value" \
    --output text 2>/dev/null || echo "None")
  if [[ "${GOT}" != "None" && -n "${GOT}" && "${GOT}" != "${WANT}" ]]; then
    echo "    !! 충돌: ${NAME} ${TYPE}"
    echo "       기존   = ${GOT}"
    echo "       변경예정= ${WANT}"
    CONFLICTS=$((CONFLICTS+1))
  fi
done
if [[ ${CONFLICTS} -gt 0 && "${FORCE:-0}" != "1" ]]; then
  echo "!! 값이 다른 기존 레코드 ${CONFLICTS}건 — 덮어쓰지 않고 중단합니다." >&2
  echo "   내용 확인 후 의도한 변경이면:  FORCE=1 $0 ${PROFILE}" >&2
  exit 1
fi
[[ ${CONFLICTS} -gt 0 ]] && echo "    FORCE=1 — ${CONFLICTS}건 덮어씀" || echo "    충돌 없음"

echo "==> [4/5] Route53 레코드 UPSERT"
CHANGE_BATCH=$(cat <<EOF
{
  "Comment": "SES sending (DKIM/MAILFROM/DMARC) + SES receiving MX for ${RECV_DOMAIN}",
  "Changes": [
    {"Action":"UPSERT","ResourceRecordSet":{"Name":"${T1}._domainkey.${DOMAIN}","Type":"CNAME","TTL":${TTL},"ResourceRecords":[{"Value":"${T1}.dkim.amazonses.com"}]}},
    {"Action":"UPSERT","ResourceRecordSet":{"Name":"${T2}._domainkey.${DOMAIN}","Type":"CNAME","TTL":${TTL},"ResourceRecords":[{"Value":"${T2}.dkim.amazonses.com"}]}},
    {"Action":"UPSERT","ResourceRecordSet":{"Name":"${T3}._domainkey.${DOMAIN}","Type":"CNAME","TTL":${TTL},"ResourceRecords":[{"Value":"${T3}.dkim.amazonses.com"}]}},
    {"Action":"UPSERT","ResourceRecordSet":{"Name":"${MAILFROM_DOMAIN}","Type":"MX","TTL":${TTL},"ResourceRecords":[{"Value":"10 feedback-smtp.${REGION}.amazonses.com"}]}},
    {"Action":"UPSERT","ResourceRecordSet":{"Name":"${MAILFROM_DOMAIN}","Type":"TXT","TTL":${TTL},"ResourceRecords":[{"Value":"\"v=spf1 include:amazonses.com ~all\""}]}},
    {"Action":"UPSERT","ResourceRecordSet":{"Name":"_dmarc.${DOMAIN}","Type":"TXT","TTL":${TTL},"ResourceRecords":[{"Value":"\"v=DMARC1; p=none; rua=mailto:${DMARC_RUA}\""}]}},
    {"Action":"UPSERT","ResourceRecordSet":{"Name":"${RECV_DOMAIN}","Type":"MX","TTL":${TTL},"ResourceRecords":[{"Value":"10 inbound-smtp.${REGION}.amazonaws.com"}]}}
  ]
}
EOF
)
CHANGE_ID=$($AWS route53 change-resource-record-sets \
  --hosted-zone-id "${ZONE_ID}" \
  --change-batch "${CHANGE_BATCH}" \
  --query "ChangeInfo.Id" --output text)
echo "    change submitted: ${CHANGE_ID} (전파 대기)"
$AWS route53 wait resource-record-sets-changed --id "${CHANGE_ID}"
echo "    Route53 INSYNC"

echo "==> [5/5] DKIM 검증 대기 (SES가 DNS 확인, 보통 수 분)"
STATUS="PENDING"
for i in $(seq 1 30); do
  STATUS=$($AWS sesv2 get-email-identity --email-identity "${DOMAIN}" \
    --query "DkimAttributes.Status" --output text)
  echo "    DKIM status: ${STATUS} (${i}/30)"
  [[ "${STATUS}" == "SUCCESS" ]] && break
  [[ "${STATUS}" == "FAILED" ]] && { echo "!! DKIM 검증 실패 — DNS 레코드 확인 필요" >&2; exit 1; }
  sleep 20
done
if [[ "${STATUS}" != "SUCCESS" ]]; then
  echo "!! DKIM 검증 타임아웃 (status=${STATUS})." >&2
  echo "   레코드는 등록됐고 SES 재확인은 최대 72시간 걸릴 수 있습니다." >&2
  echo "   잠시 후 재실행하면 이어서 확인합니다 (멱등)." >&2
  exit 1
fi

echo ""
echo "완료. 다음: ./02-ses-receiving.sh ${PROFILE}"
