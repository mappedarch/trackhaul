# Fleet Intelligence Assistant prompt — v1
module "fleet_assistant_prompt" {
  source = "../../modules/prompt-store"

  environment    = var.environment
  prompt_name    = "fleet-assistant"
  prompt_version = "v1"
  kms_key_arn    = aws_kms_key.llmops.arn
  prompt_path_root = local.prompt_path_root

  prompt_text = file("${path.module}/prompts/fleet-assistant-v1.txt")
}

# Eval framework — S3 bucket for golden dataset and eval results
module "eval_framework" {
  source = "../../modules/eval-framework"

  environment = var.environment
  naming_prefix = local.prefix
  kms_key_arn   = aws_kms_key.llmops.arn
  eval_results_retention_days = 365
}

# Bedrock wrapper — single instrumentation point for all LLM invocations
module "lambda_bedrock_wrapper" {
  source = "../../modules/lambda-bedrock-wrapper"

  environment                    = var.environment
  extension_layer_arn            = var.extension_layer_arn
  ssm_prompt_active_pointer_name = module.fleet_assistant_prompt.prompt_active_pointer_name
  ssm_prompt_active_pointer_arn  = module.fleet_assistant_prompt.prompt_active_pointer_arn
  ssm_prompt_version_arn         = module.fleet_assistant_prompt.prompt_version_arn
  kms_key_arn                    = aws_kms_key.llmops.arn
  simulation_mode                = var.simulation_mode
  ssm_parameter_ttl              = 60
}
# Drift detector — daily response length drift check across query types
module "drift_detector" {
  source = "../../modules/drift-detector"

  environment    = var.environment
  naming_prefix  = local.prefix
  kms_key_arn    = aws_kms_key.llmops.arn
  prompt_version = "active"
}

# Feedback loop — captures dispatcher ratings and reingests corrections into golden dataset
module "feedback_loop" {
  source = "../../modules/feedback-loop"

  environment           = var.environment
  kms_key_arn           = aws_kms_key.llmops.arn
  log_retention_days    = 30
  golden_dataset_bucket = module.eval_framework.eval_bucket_name
  golden_dataset_prefix = "golden-dataset"
  tags                  = local.common_tags
}
