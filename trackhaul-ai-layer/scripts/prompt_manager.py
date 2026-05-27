"""
TrackHaul Prompt Manager
Loads versioned prompt templates and builds final prompt payloads for Bedrock.
No PII handling — truck IDs only. All prompt constraints enforced in system prompt.
"""

import json
import logging
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

# Supported contracts
VALID_CONTRACTS = {
    "fleet-query",
    "fault-diagnosis",
    "anomaly-explanation",
    "incident-summary",
}

# Map contract name to filename
CONTRACT_FILE_MAP = {
    "fleet-query": "fleet_query.json",
    "fault-diagnosis": "fault_diagnosis.json",
    "anomaly-explanation": "anomaly_explanation.json",
    "incident-summary": "incident_summary.json",
}


class PromptManager:
    """
    Loads prompt templates from versioned JSON files.
    Builds Bedrock-compatible message payloads with context injection.
    """

    def __init__(self, prompts_dir: Optional[str] = None, version: str = "v1"):
        """
        Args:
            prompts_dir: Absolute path to prompts directory. Defaults to ../prompts relative to this script.
            version: Prompt version folder to load from. Default 'v1'.
        """
        if prompts_dir:
            self.prompts_dir = Path(prompts_dir)
        else:
            # Resolve relative to this script's location
            self.prompts_dir = Path(__file__).parent.parent / "prompts"

        self.version = version
        self._cache: dict = {}
        logger.info(f"PromptManager initialised — prompts dir: {self.prompts_dir}, version: {version}")

    def load_contract(self, contract: str) -> dict:
        """
        Load and cache a prompt contract by name.

        Args:
            contract: One of VALID_CONTRACTS

        Returns:
            Parsed prompt template dict
        """
        if contract not in VALID_CONTRACTS:
            raise ValueError(f"Unknown contract '{contract}'. Valid: {VALID_CONTRACTS}")

        # Return cached if already loaded
        if contract in self._cache:
            return self._cache[contract]

        file_name = CONTRACT_FILE_MAP[contract]
        file_path = self.prompts_dir / self.version / file_name

        if not file_path.exists():
            raise FileNotFoundError(f"Prompt file not found: {file_path}")

        with open(file_path, "r", encoding="utf-8") as f:
            template = json.load(f)

        self._cache[contract] = template
        logger.info(f"Loaded contract '{contract}' version {template.get('version', 'unknown')}")
        return template

    def build_payload(self, contract: str, query: str, context: str) -> dict:
        """
        Build a complete Bedrock converse API payload for a given contract.

        Args:
            contract: Prompt contract name
            query: User query or anomaly/incident data string
            context: Retrieved RAG context to inject

        Returns:
            Dict with system, messages, max_tokens, temperature — ready for Bedrock converse API
        """
        template = self.load_contract(contract)

        # Build user message from template
        user_content = template["user_template"].format(
            context=context,
            query=query,
        )

        # Prepend few-shot examples if present
        # Bedrock converse API requires content as a list of typed blocks
        messages = []
        for example in template.get("few_shot", []):
            example_user = template["user_template"].format(
                context=example["context"],
                query=example["query"],
            )
            messages.append({
                "role": "user",
                "content": [{"text": example_user}]
            })
            messages.append({
                "role": "assistant",
                "content": [{"text": example["response"]}]
            })

        messages.append({
            "role": "user",
            "content": [{"text": user_content}]
        })

        payload = {
            "system": template["system_prompt"],
            "messages": messages,
            "max_tokens": template.get("max_tokens", 512),
            "temperature": template.get("temperature", 0.1),
            "contract_version": template.get("version", "unknown"),
            "contract_name": contract,
        }

        return payload

    def get_version_info(self, contract: str) -> dict:
        """Return version metadata for a contract — used for logging and audit."""
        template = self.load_contract(contract)
        return {
            "contract": contract,
            "version": template.get("version"),
            "description": template.get("description"),
        }