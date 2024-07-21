terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    helm = {
      source = "hashicorp/helm"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/shin_config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/shin_config"
  }
}