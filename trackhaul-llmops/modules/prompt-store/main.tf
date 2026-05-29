# Stores the actual prompt text — encrypted with KMS
# Path: /trackhaul/prompts/{name}/{version}
resource "aws_ssm_parameter" "prompt_version" {
  name = "${var.prompt_path_root}/${var.prompt_name}/${var.prompt_version}"
  description = "Prompt version ${var.prompt_version} for ${var.prompt_name}"
  type        = "SecureString"
  value       = var.prompt_text
  key_id      = var.kms_key_arn

  tags = {
    environment = var.environment
    prompt_name = var.prompt_name
    version     = var.prompt_version
    managed_by  = "terraform"
  }
}

# Stores which version is currently active — Lambda reads this first
# Path: /trackhaul/prompts/{name}/active
resource "aws_ssm_parameter" "prompt_active_pointer" {
  name = "${var.prompt_path_root}/${var.prompt_name}/active"
  description = "Active version pointer for ${var.prompt_name}"
  type        = "String"
  value       = var.prompt_version

  tags = {
    environment = var.environment
    prompt_name = var.prompt_name
    managed_by  = "terraform"
  }
}