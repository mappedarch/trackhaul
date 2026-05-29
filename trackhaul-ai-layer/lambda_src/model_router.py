"""
Model router for TrackHaul AI layer.
Classifies incoming queries and routes to the cheapest appropriate Bedrock model.
All routing logic is centralised here — never scattered across calling functions.
"""

import re
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Model IDs — eu-west-1 only for GDPR compliance
MODELS = {
    "haiku":  {"model_id": "eu.anthropic.claude-haiku-4-5-20251001-v1:0",  "region": "eu-west-1"},
    "sonnet": {"model_id": "eu.anthropic.claude-sonnet-4-5-20250929-v1:0", "region": "eu-central-1"},
}

# Simple lookup patterns — these queries never need RAG or complex reasoning
SIMPLE_PATTERNS = [
    r"fault code\s+[A-Z0-9]+",        # "what is fault code P0300"
    r"how many trucks",                # "how many trucks are active"
    r"status of truck\s+TH-\d+",      # "status of truck TH-4821"
    r"is truck\s+TH-\d+\s+active",    # "is truck TH-4821 active"
    r"last seen",                      # "when was TH-4821 last seen"
]

# Compiled once at cold start — not on every invocation
SIMPLE_PATTERNS_COMPILED = [re.compile(p, re.IGNORECASE) for p in SIMPLE_PATTERNS]


def route(query: str) -> dict:
    query = query.strip()
    model_key = "haiku" if _is_simple(query) else "sonnet"
    model = MODELS[model_key]
    logger.info(f"Routed query to {model_key} | query_preview={query[:80]}")
    return {
        "model_id": model["model_id"],
        "region":   model["region"],
        "tier":     model_key,
    }


def _is_simple(query: str) -> bool:
    """
    Returns True if the query matches a known simple lookup pattern.
    Simple queries do not require RAG retrieval or multi-step reasoning.
    """
    for pattern in SIMPLE_PATTERNS_COMPILED:
        if pattern.search(query):
            return True
    return False
