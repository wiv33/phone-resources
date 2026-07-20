#!/usr/bin/env bash
# =============================================================================
# 02 - SES 이메일 수신 파이프라인: S3 저장 + SNS 알림
#
# 생성하는 것:
#   - S3 버킷  phoneshin-mail-inbox-<account>  (private, SES만 PutObject 허용)
#   - SNS 토픽 phoneshin-mail-received         (SES publish 허용 정책 포함)
#   - SES receipt rule set  phoneshin-inbound
#       └ rule  bot-inbox-to-s3:  recipients=[bot.phoneshin.com]
#               S3Action(prefix inbox/, SNS 알림), 스팸/바이러스 스캔 ON
#   - rule set 활성화 (기존 active rule set 있으면 중단하고 알림)
#
# 사용법:  ./02-ses-receiving.sh <aws-profile>     # 01 실행 후
# 멱등:    재실행 안전
# =============================================================================
set -euo pipefail
export AWS_PAGER=""

PROFILE="${1:?사용법: $0 <aws-profile>}"
DOMAIN="phoneshin.com"
RECV_DOMAIN="bot.phoneshin.com"
REGION="ap-northeast-2"
RULE_SET="phoneshin-inbound"
RULE_NAME="bot-inbox-to-s3"
TOPIC_NAME="phoneshin-mail-received"
KEY_PREFIX="inbox/"
RETENTION_DAYS=180   # 수신 원문 보관 기간 (처리 후에도 원본은 이 기간 뒤 자동 삭제)

AWS="aws --profile ${PROFILE} --region ${REGION}"

echo "==> [0/6] 사전 확인"
ACCOUNT_ID=$($AWS sts get-caller-identity --query Account --output text)
BUCKET="phoneshin-mail-inbox-${ACCOUNT_ID}"
echo "    계정: ${ACCOUNT_ID} / 버킷: ${BUCKET}"

DKIM_STATUS=$($AWS sesv2 get-email-identity --email-identity "${DOMAIN}" \
  --query "DkimAttributes.Status" --output text 2>/dev/null || echo "MISSING")
if [[ "${DKIM_STATUS}" != "SUCCESS" ]]; then
  echo "!! ${DOMAIN} identity 미검증 상태(${DKIM_STATUS}). 01번 스크립트를 먼저 완료하세요." >&2
  echo "   (수신은 검증된 도메인의 서브도메인에만 허용됨)" >&2
  exit 1
fi

echo "==> [1/6] S3 버킷 생성 + 퍼블릭 차단"
if $AWS s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  echo "    이미 존재 — 재사용"
else
  $AWS s3api create-bucket --bucket "${BUCKET}" \
    --create-bucket-configuration "LocationConstraint=${REGION}" >/dev/null
  echo "    생성됨"
fi
$AWS s3api put-public-access-block --bucket "${BUCKET}" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# 수명주기: 수신 원문은 누구나 쓸 수 있는 경로이므로 무한 축적 방지 (denial-of-wallet)
$AWS s3api put-bucket-lifecycle-configuration --bucket "${BUCKET}" \
  --lifecycle-configuration "$(cat <<EOF
{
  "Rules": [
    {"ID":"expire-inbox","Status":"Enabled","Filter":{"Prefix":"${KEY_PREFIX}"},"Expiration":{"Days":${RETENTION_DAYS}}},
    {"ID":"abort-incomplete-mpu","Status":"Enabled","Filter":{"Prefix":""},"AbortIncompleteMultipartUpload":{"DaysAfterInitiation":7}}
  ]
}
EOF
)"
echo "    수명주기: ${KEY_PREFIX} ${RETENTION_DAYS}일 후 자동 삭제"

echo "==> [2/6] S3 버킷 정책 (SES 전용 PutObject)"
$AWS s3api put-bucket-policy --bucket "${BUCKET}" --policy "$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowSESPuts",
      "Effect": "Allow",
      "Principal": {"Service": "ses.amazonaws.com"},
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${BUCKET}/*",
      "Condition": {
        "StringEquals": {"aws:SourceAccount": "${ACCOUNT_ID}"},
        "ArnLike": {"aws:SourceArn": "arn:aws:ses:${REGION}:${ACCOUNT_ID}:receipt-rule-set/${RULE_SET}:receipt-rule/*"}
      }
    }
  ]
}
EOF
)"

echo "==> [3/6] SNS 토픽 + SES publish 정책"
TOPIC_ARN=$($AWS sns create-topic --name "${TOPIC_NAME}" --query TopicArn --output text)
echo "    topic: ${TOPIC_ARN}"
$AWS sns set-topic-attributes --topic-arn "${TOPIC_ARN}" \
  --attribute-name Policy --attribute-value "$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "OwnerFullAccess",
      "Effect": "Allow",
      "Principal": {"AWS": "*"},
      "Action": ["SNS:Subscribe","SNS:Receive","SNS:Publish","SNS:GetTopicAttributes","SNS:SetTopicAttributes","SNS:ListSubscriptionsByTopic","SNS:DeleteTopic","SNS:AddPermission","SNS:RemovePermission"],
      "Resource": "${TOPIC_ARN}",
      "Condition": {"StringEquals": {"AWS:SourceOwner": "${ACCOUNT_ID}"}}
    },
    {
      "Sid": "AllowSESPublish",
      "Effect": "Allow",
      "Principal": {"Service": "ses.amazonaws.com"},
      "Action": "SNS:Publish",
      "Resource": "${TOPIC_ARN}",
      "Condition": {
        "StringEquals": {"aws:SourceAccount": "${ACCOUNT_ID}"},
        "ArnLike": {"aws:SourceArn": "arn:aws:ses:${REGION}:${ACCOUNT_ID}:receipt-rule-set/${RULE_SET}:receipt-rule/*"}
      }
    }
  ]
}
EOF
)"

echo "==> [4/6] receipt rule set: ${RULE_SET}"
if $AWS ses describe-receipt-rule-set --rule-set-name "${RULE_SET}" >/dev/null 2>&1; then
  echo "    이미 존재 — 재사용"
else
  $AWS ses create-receipt-rule-set --rule-set-name "${RULE_SET}"
  echo "    생성됨"
fi

echo "==> [5/6] receipt rule: ${RULE_NAME} (recipients=${RECV_DOMAIN})"
# TlsPolicy=Require: STARTTLS 없는 평문 SMTP 수신 거부 (현실적 발신자는 전부 지원)
RULE_JSON=$(cat <<EOF
{
  "Name": "${RULE_NAME}",
  "Enabled": true,
  "TlsPolicy": "Require",
  "Recipients": ["${RECV_DOMAIN}"],
  "Actions": [
    {
      "S3Action": {
        "BucketName": "${BUCKET}",
        "ObjectKeyPrefix": "${KEY_PREFIX}",
        "TopicArn": "${TOPIC_ARN}"
      }
    }
  ],
  "ScanEnabled": true
}
EOF
)
# 방금 넣은 S3/SNS 정책이 SES 검증에 반영되기까지 지연될 수 있어 재시도
RULE_OK=0
for attempt in $(seq 1 6); do
  if $AWS ses describe-receipt-rule --rule-set-name "${RULE_SET}" --rule-name "${RULE_NAME}" >/dev/null 2>&1; then
    ERR=$($AWS ses update-receipt-rule --rule-set-name "${RULE_SET}" --rule "${RULE_JSON}" 2>&1) \
      && { echo "    업데이트됨"; RULE_OK=1; break; }
  else
    ERR=$($AWS ses create-receipt-rule --rule-set-name "${RULE_SET}" --rule "${RULE_JSON}" 2>&1) \
      && { echo "    생성됨"; RULE_OK=1; break; }
  fi
  echo "    시도 ${attempt}/6 실패 (정책 전파 대기 중일 수 있음): ${ERR}"
  sleep 10
done
if [[ ${RULE_OK} -ne 1 ]]; then
  echo "!! receipt rule 생성/갱신 실패 — 위 오류 확인 후 재실행 (멱등)" >&2
  exit 1
fi

echo "==> [6/6] rule set 활성화"
ACTIVE=$($AWS ses describe-active-receipt-rule-set --query "Metadata.Name" --output text 2>/dev/null || echo "None")
if [[ "${ACTIVE}" == "${RULE_SET}" ]]; then
  echo "    이미 활성 상태"
elif [[ "${ACTIVE}" == "None" || -z "${ACTIVE}" ]]; then
  $AWS ses set-active-receipt-rule-set --rule-set-name "${RULE_SET}"
  echo "    활성화됨"
else
  echo "!! 다른 rule set '${ACTIVE}' 이 이미 활성 상태입니다." >&2
  echo "   교체하려면:  $AWS ses set-active-receipt-rule-set --rule-set-name ${RULE_SET}" >&2
  exit 1
fi

echo ""
echo "완료. 검증: ./verify.sh ${PROFILE}"
echo "테스트: 아무 주소나 (예: gmail) -> test@${RECV_DOMAIN} 로 메일 발송 후"
echo "        $AWS s3 ls s3://${BUCKET}/${KEY_PREFIX}"
