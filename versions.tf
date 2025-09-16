provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Terraform   = "true"
      ClusterId = var.cluster_name
    }
  }
}

provider "aws" {
  alias  = "daytona"
  region = var.region

  access_key = var.DAYTONA_ACCESS_KEY
  secret_key = var.DAYTONA_SECRET_KEY

  default_tags {
    tags = {
      Terraform   = "true"
      ClusterId = var.cluster_name
    }
  }
}