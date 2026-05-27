terraform {
  required_providers {
    pinecone = {
      source  = "pinecone-io/pinecone"
      version = "~> 0.7"
    }
  }
}

resource "pinecone_index" "fleet" {
  name      = "trackhaul-fleet-${var.environment}"
  dimension = 1024   # Titan Embed Text V2 output dimension
  metric    = "cosine"

  spec = {
    serverless = {
      cloud  = "aws"
      region = "us-east-1"  # Free tier only — prod would use Aurora pgvector in eu-west-1
    }
  }
}