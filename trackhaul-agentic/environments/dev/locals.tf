locals {
  prefix = "trackhaul-agentic-${var.environment}"

  common_tags = {
    environment = var.environment
    component   = "agentic"
  }
}