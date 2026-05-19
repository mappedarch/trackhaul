# -------------------------------------------------------------------
# Cognito User Pool — TrackHaul fleet ops identity store
# Groups: ops-admin, dispatcher, auditor
# No self-registration — users provisioned by ops-admin only
# -------------------------------------------------------------------

resource "aws_cognito_user_pool" "fleet" {
  name = "${var.project}-${var.environment}-fleet-users"

  # Prevent accidental destruction — User Pool deletion is irreversible
  lifecycle {
    prevent_destroy = true
  }

  # Username is email — no ambiguity for fleet ops staff
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Password policy 
  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 3
  }

  # MFA — optional per user, SMS or TOTP
  mfa_configuration = "OPTIONAL"

  software_token_mfa_configuration {
    enabled = true
  }

  # Account recovery via email only — no phone dependency
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Admin-only user creation — no self-signup
  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# -------------------------------------------------------------------
# User Pool Client — used by API consumers (Postman, frontend)
# No client secret — allows direct token exchange without backend relay
# -------------------------------------------------------------------

resource "aws_cognito_user_pool_client" "fleet_api" {
  name         = "${var.project}-${var.environment}-fleet-api-client"
  user_pool_id = aws_cognito_user_pool.fleet.id

  # No secret — allows Postman and CLI testing without secret exchange
  generate_secret = false

  # Token validity — mirrors fleet ops shift pattern
  access_token_validity  = var.token_validity_hours
  id_token_validity      = var.token_validity_hours
  refresh_token_validity = var.refresh_token_validity_hours

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "hours"
  }

  # USER_PASSWORD_AUTH for Postman testing
  # REFRESH_TOKEN_AUTH for token refresh
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  # Prevent token leakage — no OAuth flows needed for API-only client
  allowed_oauth_flows_user_pool_client = false
}

# -------------------------------------------------------------------
# Groups — map to IAM roles via cognito:groups claim in JWT
# -------------------------------------------------------------------

resource "aws_cognito_user_group" "ops_admin" {
  name         = "ops-admin"
  user_pool_id = aws_cognito_user_pool.fleet.id
  description  = "Fleet operations administrators — full read/write access"
  precedence   = 1
}

resource "aws_cognito_user_group" "dispatcher" {
  name         = "dispatcher"
  user_pool_id = aws_cognito_user_pool.fleet.id
  description  = "Dispatchers — read vehicles, write assignments"
  precedence   = 2
}

resource "aws_cognito_user_group" "auditor" {
  name         = "auditor"
  user_pool_id = aws_cognito_user_pool.fleet.id
  description  = "Auditors — read-only access to all fleet records"
  precedence   = 3
}