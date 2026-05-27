output "s3_bucket_name" {
  value = module.s3_kb_source.bucket_name
}

output "pinecone_index_name" {
  value = module.pinecone.index_name
}

output "pinecone_index_host" {
  value = module.pinecone.index_host
}