# 상태 백엔드: ../bootstrap-state.sh 로 버킷/잠금테이블 선생성 후 terraform init
# 다른 프로파일로 운영하려면: terraform init -backend-config="profile=<이름>"
terraform {
  required_version = ">= 1.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.55" # 6.55.0 으로 구축·검증 (레포 .gitignore 가 lock 파일을 무시하므로 여기서 조임)
    }
  }

  backend "s3" {
    bucket         = "phoneshin-tfstate-211125461385"
    key            = "mail-infra/terraform.tfstate"
    region         = "ap-northeast-2"
    profile        = "auto"
    dynamodb_table = "phoneshin-tfstate-lock"
    encrypt        = true
  }
}
