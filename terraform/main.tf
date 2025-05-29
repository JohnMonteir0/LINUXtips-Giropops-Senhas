module "eks" {
  source       = "git@github.com:JohnMonteir0/k8s_with_terraform.git"
  cidr_block   = "10.0.0.0/16"
  project_name = "giropops"
}