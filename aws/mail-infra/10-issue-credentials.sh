#!/usr/bin/env bash
# phone-api 메일 소비자 IAM access key 발급 → shin 클러스터 k8s Secret 반영.
# TF state 에 시크릿을 남기지 않기 위해 Terraform 밖에서 발급한다.
# 시크릿 값은 화면에 출력하지 않는다.
#
# 사용법: ./10-issue-credentials.sh [aws-profile]   (기본: auto)
# 재실행: 새 키 발급 후 k8s Secret 교체. IAM 키는 사용자당 최대 2개 —
#         교체 완료 확인 후 옛 키는 수동 삭제할 것 (스크립트가 목록 출력).
set -euo pipefail
export AWS_PAGER=""

PROFILE="${1:-auto}"
REGION="ap-northeast-2"
IAM_USER="phone-api-mail-consumer"
K8S_NS="phoneshin"
K8S_SECRET="phone-api-mail-aws"
KUBECONFIG_PATH="${KUBECONFIG:-$HOME/.kube/shin_config}"
AWS="aws --profile ${PROFILE} --region ${REGION}"

# 키를 발급하기 전에 k8s 도달 가능 여부부터 확인 (실패 시 고아 키가 생기므로)
echo "==> k8s 연결 확인 (${K8S_NS} 네임스페이스)"
if ! kubectl --kubeconfig "${KUBECONFIG_PATH}" --context shin get ns "${K8S_NS}" --request-timeout=8s >/dev/null 2>&1; then
  echo "!! shin 클러스터에 연결할 수 없습니다 (VPN 확인). 키 발급 전 중단합니다." >&2
  exit 1
fi

echo "==> 기존 키 목록 (2개면 하나 삭제 후 재실행 필요)"
$AWS iam list-access-keys --user-name "${IAM_USER}" \
  --query "AccessKeyMetadata[].{Id:AccessKeyId,Status:Status,Created:CreateDate}" --output table

echo "==> 새 access key 발급"
CREDS_JSON=$($AWS iam create-access-key --user-name "${IAM_USER}" --output json)
KEY_ID=$(echo "${CREDS_JSON}" | python3 -c "import sys,json;print(json.load(sys.stdin)['AccessKey']['AccessKeyId'])")
echo "    AccessKeyId: ${KEY_ID} (secret 은 비출력)"

echo "==> k8s Secret ${K8S_NS}/${K8S_SECRET} 반영"
SECRET=$(echo "${CREDS_JSON}" | python3 -c "import sys,json;print(json.load(sys.stdin)['AccessKey']['SecretAccessKey'])")
kubectl --kubeconfig "${KUBECONFIG_PATH}" --context shin -n "${K8S_NS}" \
  create secret generic "${K8S_SECRET}" \
  --from-literal=AWS_ACCESS_KEY_ID="${KEY_ID}" \
  --from-literal=AWS_SECRET_ACCESS_KEY="${SECRET}" \
  --from-literal=AWS_REGION="${REGION}" \
  --dry-run=client -o yaml | kubectl --kubeconfig "${KUBECONFIG_PATH}" --context shin apply -f -
unset SECRET CREDS_JSON

echo ""
echo "완료. phone-api Deployment 에서 envFrom secretRef ${K8S_SECRET} 로 주입하세요."
echo "키 교체 시: 배포 반영 확인 후  $AWS iam delete-access-key --user-name ${IAM_USER} --access-key-id <옛키>"
