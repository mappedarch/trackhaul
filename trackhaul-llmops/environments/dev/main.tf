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