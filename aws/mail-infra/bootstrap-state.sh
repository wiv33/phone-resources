#!/usr/bin/env bash
# Terraform 상태 백엔드 부트스트랩 (1회): 상태 버킷 + DynamoDB 잠금 테이블.
# 사용법: ./bootstrap-state.sh [aws-profile]   (기본: auto)
set -euo pipefail
export AWS_PAGER=""

PROFILE="${1:-auto}"
REGION="ap-northeast-2"
AWS="aws --profile ${PROFILE} --region ${REGION}"

ACCOUNT_ID=$($AWS sts get-caller-identity --query Account --output text)
BUCKET="phoneshin-tfstate-${ACCOUNT_ID}"
LOCK_TABLE="phoneshin-tfstate-lock"

echo "==> 상태 버킷: ${BUCKET}"
if $AWS s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  echo "    이미 존재"
else
  $AWS s3api create-bucket --bucket "${BUCKET}" \
    --create-bucket-configuration "LocationConstraint=${REGION}" >/dev/null
  echo "    생성됨"
fi
$AWS s3api put-bucket-versioning --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled
$AWS s3api put-bucket-encryption --bucket "${BUCKET}" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
$AWS s3api put-public-access-block --bucket "${BUCKET}" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "==> 잠금 테이블: ${LOCK_TABLE}"
if $AWS dynamodb describe-table --table-name "${LOCK_TABLE}" >/dev/null 2>&1; then
  echo "    이미 존재"
else
  $AWS dynamodb create-table --table-name "${LOCK_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST >/dev/null
  $AWS dynamodb wait table-exists --table-name "${LOCK_TABLE}"
  echo "    생성됨"
fi

echo "완료. 다음: cd terraform && terraform init"
