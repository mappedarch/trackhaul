locals {
  # Naming prefix used consistently across all resources
  prefix = "trackhaul-aiops-${var.environment}"

  # Environment shorthand
  environment = var.environment

  # Log retention — 30 days operational window per LLMOps strategy
  log_retention_days = 30
}
