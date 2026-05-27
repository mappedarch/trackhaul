resource "aws_bedrock_guardrail" "fleet_assistant" {
  name                      = "${var.project}-${var.environment}-fleet-guardrail"
  description               = "GDPR and safety guardrail for TrackHaul Fleet Intelligence Assistant"
  blocked_input_messaging   = "This query contains personal data that cannot be processed. Please rephrase using truck IDs only."
  blocked_outputs_messaging = "The response was blocked because it contained personal data. Please contact your administrator."

  # PII detection — ANONYMISE on input, BLOCK on output
  sensitive_information_policy_config {
    pii_entities_config {
      type   = "NAME"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "EMAIL"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "PHONE"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "DRIVER_ID"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "USERNAME"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "UK_NATIONAL_INSURANCE_NUMBER"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "VEHICLE_IDENTIFICATION_NUMBER"
      action = "BLOCK"
    }
  }

  # Denied topics — queries that must never be answered
  topic_policy_config {
    topics_config {
      name       = "driver-personal-data"
      type       = "DENY"
      definition = "Any query requesting personal information about drivers including names, addresses, salaries, personal contact details, or identification numbers."
      examples   = [
        "What is the home address of the driver of truck TH-4821?",
        "Show me the salary details for drivers in Poland",
        "Give me the national ID of driver on route DE-99"
      ]
    }
  }



  # Content filters — block harmful content at moderate threshold
  content_policy_config {
    filters_config {
      type            = "HATE"
      input_strength  = "MEDIUM"
      output_strength = "MEDIUM"
    }
    filters_config {
      type            = "INSULTS"
      input_strength  = "MEDIUM"
      output_strength = "MEDIUM"
    }
    filters_config {
      type            = "SEXUAL"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "VIOLENCE"
      input_strength  = "MEDIUM"
      output_strength = "MEDIUM"
    }
  }
}

# Publish a version — Lambda references a specific version, not DRAFT
resource "aws_bedrock_guardrail_version" "fleet_assistant" {
  guardrail_arn = aws_bedrock_guardrail.fleet_assistant.guardrail_arn
  description   = "Initial production version"
}