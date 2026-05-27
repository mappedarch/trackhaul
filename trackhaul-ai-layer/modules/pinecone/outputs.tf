output "index_name" { value = pinecone_index.fleet.name }
output "index_host" { value = "https://${pinecone_index.fleet.host}" }