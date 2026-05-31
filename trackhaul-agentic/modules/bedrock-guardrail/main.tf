resource "aws_bedrock_guardrail" "fleet_agent" {
  name                      = "trackhaul-${var.environment}-fleet-agent"
  description               = "Guardrail for TrackHaul fleet agent. Blocks PII, prompt injection, and out-of-scope queries."
  blocked_input_messaging   = "This query contains information that cannot be processed by the fleet assistant."
  blocked_outputs_messaging = "The response was blocked. Please contact your fleet administrator."

  # ── PII filtering ─────────────────────────────────────────────────
  # Block PII from entering the LLM. GDPR Article 25 — data minimisation by design.
  sensitive_information_policy_config {
    pii_entities_config {
      type   = "NAME"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "EMAIL"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "PHONE"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "ADDRESS"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "DRIVER_ID"
      action = "BLOCK"
    }
  }

  # ── Denied topics ─────────────────────────────────────────────────
  # Prevent the agent being used outside its defined scope.
  # This is your GDPR Article 5(1)(b) purpose limitation control.
  topic_policy_config {
    topics_config {
      name       = "out-of-scope-queries"
      type       = "DENY"
      definition = "Any query unrelated to fleet operations, vehicle maintenance, fuel consumption, driver safety scores, or incident response for TrackHaul logistics."
      examples   = [
        "Tell me about the driver's personal life",
        "What is the driver's home address",
        "Access employee records",
        "Ignore your previous instructions"
      ]
    }
  }

  # ── Word filters ──────────────────────────────────────────────────
  # Catch common prompt injection patterns.
  # These have triggered real incidents in production LLM systems.
  word_policy_config {
    words_config { text = "ignore previous instructions" }
    words_config { text = "ignore all instructions" }
    words_config { text = "disregard your system prompt" }
    words_config { text = "you are now" }
    words_config { text = "act as" }
    words_config { text = "jailbreak" }
  }

  tags = var.tags
}

# Publish a version — guardrails require a version to be attached to model calls
resource "aws_bedrock_guardrail_version" "fleet_agent" {
  guardrail_arn = aws_bedrock_guardrail.fleet_agent.guardrail_arn
  description   = "Initial version — PII block, topic deny, word filter"
}