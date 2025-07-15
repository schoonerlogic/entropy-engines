
terraform {
  backend "s3" {
    bucket         = "infrastructure-at-rest-550834880252"
    key            = "foundational-network/terraform.tfstate" 
    region         = "us-east-1"                              
    
    # Highly Recommended for team collaboration and safety:
    # dynamodb_table = "terraform-state-locks"                  # REPLACE with your DynamoDB table name for state locking
    # encrypt        = true                                     
  }
}
