# modules/budgets/main.tf
# AWS Budgets — cost controls and alerts per account
# Alerts sent via email when thresholds are breached
# Unexpected cost spikes can indicate security incidents

# -------------------------------------------------------
# LOCAL VALUES
# Define budget limits per account in one place
# Easy to update without touching resource code
# -------------------------------------------------------
locals {
  account_budgets = {
    management = {
      account_id = var.management_account_id
      limit      = "10"
      name       = "trackhaul-management-budget"
    }
    security = {
      account_id = var.security_account_id
      limit      = "10"
      name       = "trackhaul-security-budget"
    }
    log_archive = {
      account_id = var.log_archive_account_id
      limit      = "10"
      name       = "trackhaul-log-archive-budget"
    }
    dev = {
      account_id = var.dev_account_id
      limit      = "10"
      name       = "trackhaul-dev-budget"
    }
    prod = {
      account_id = var.prod_account_id
      limit      = "10"
      name       = "trackhaul-prod-budget"
    }
  }
}

# -------------------------------------------------------
# BUDGETS PER ACCOUNT
# One budget per account with two alert thresholds
# 80% — warning, time to investigate
# 100% — critical, immediate action required
# -------------------------------------------------------
resource "aws_budgets_budget" "accounts" {
  for_each = local.account_budgets

  name         = each.value.name
  budget_type  = "COST"
  limit_amount = each.value.limit
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Alert at 80% — warning
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }

  # Alert at 100% — critical
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  tags = {
    Purpose = "Cost-Control"
    GDPR    = "true"
  }
}