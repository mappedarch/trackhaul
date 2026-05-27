terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

resource "null_resource" "bedrock_kb" {
  triggers = {
    role_arn      = aws_iam_role.bedrock_kb.arn
    pinecone_host = var.pinecone_host
    secret_arn    = var.pinecone_secret_arn
    region        = var.aws_region
  }

  provisioner "local-exec" {
    command     = <<EOT
aws bedrock-agent create-knowledge-base \
  --name "trackhaul-fleet-kb-${var.environment}" \
  --role-arn "${aws_iam_role.bedrock_kb.arn}" \
  --knowledge-base-configuration '{"type":"VECTOR","vectorKnowledgeBaseConfiguration":{"embeddingModelArn":"arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0"}}' \
  --storage-configuration '{"type":"PINECONE","pineconeConfiguration":{"connectionString":"${var.pinecone_host}","credentialsSecretArn":"${var.pinecone_secret_arn}","fieldMapping":{"textField":"text","metadataField":"metadata"}}}' \
  --region ${var.aws_region} \
  --query 'knowledgeBase.knowledgeBaseId' \
  --output text
EOT
    interpreter = ["bash", "-c"]
  }
}