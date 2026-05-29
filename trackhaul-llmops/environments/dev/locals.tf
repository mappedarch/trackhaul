locals {
  # Naming prefix used consistently across all resources
  prefix = "trackhaul-llmops-${var.environment}"

  # SSM prompt path root — single definition, referenced everywhere
  prompt_path_root = "/trackhaul/llmops/prompts"

  # Common tags merged with any resource-specific tags
  common_tags = {
    environment = var.environment
    component   = "llmops"
  }
}