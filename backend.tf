# Remote state backend.
terraform {
  backend "s3" {
    bucket       = "navindadev-terraform-state"
    key          = "vpc-infra/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
    # dynamodb_table = "vpc-terraform-locks"
  }
}
