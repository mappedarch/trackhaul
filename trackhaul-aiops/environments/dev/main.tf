module "aiops_explainer" {
  source = "../../modules/aiops_explainer"

  environment      = local.environment
  aws_region       = var.aws_region
  aws_account_id   = var.aws_account_id
  event_bus_name   = var.event_bus_name
  bedrock_region   = var.bedrock_region
  bedrock_model_id = var.bedrock_model_id
  log_retention_days = local.log_retention_days
}
