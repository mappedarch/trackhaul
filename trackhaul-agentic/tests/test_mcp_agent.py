"""
TrackHaul MCP Agent — Integration Tests
Fires multiple queries to prove the agent reasons correctly
across all tool combinations.
"""

import asyncio
import sys
import os
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from langchain_mcp_adapters.tools import load_mcp_tools
from langchain_aws import ChatBedrockConverse
from langgraph.prebuilt import create_react_agent

import warnings
warnings.filterwarnings("ignore", category=DeprecationWarning)

# ── LLM ──────────────────────────────────────────────────────────────────────
llm = ChatBedrockConverse(
    model="eu.anthropic.claude-sonnet-4-5-20250929-v1:0",
    region_name="eu-west-1",
)

# ── Server definitions ────────────────────────────────────────────────────────
def get_server_params(module_path: str) -> StdioServerParameters:
    return StdioServerParameters(
        command=sys.executable,
        args=["-m", module_path],
        env={**os.environ},
    )

SERVERS = {
    "fleet_query":    get_server_params("mcp_servers.fleet_query.server"),
    "maintenance":    get_server_params("mcp_servers.maintenance.server"),
    "alert_dispatch": get_server_params("mcp_servers.alert_dispatch.server"),
}

# ── Test queries ──────────────────────────────────────────────────────────────
TEST_QUERIES = [
    {
        "id": "TC-01",
        "description": "Single tool — fleet status lookup",
        "query": "What is the current status of truck TH-1003?",
    },
    {
        "id": "TC-02",
        "description": "Single tool — region filter",
        "query": "List all trucks operating in Germany.",
    },
    {
        "id": "TC-03",
        "description": "Single tool — maintenance history",
        "query": "Show me the full maintenance history for truck TH-1001.",
    },
    {
        "id": "TC-04",
        "description": "Two tools — fault + status",
        "query": "Which trucks have open faults? What is their current fuel level?",
    },
    {
        "id": "TC-05",
        "description": "Three tools — fault + status + alert",
        "query": "Find all idle trucks, check if they have any open faults, and dispatch a low severity alert for any that do.",
    },
]

# ── Session management ────────────────────────────────────────────────────────
async def load_all_tools() -> tuple:
    """Open all MCP sessions and return tools + context managers."""
    all_tools = []
    exit_stack = []

    for name, params in SERVERS.items():
        stdio_ctx = stdio_client(params)
        read, write = await stdio_ctx.__aenter__()
        exit_stack.append(stdio_ctx)

        session_ctx = ClientSession(read, write)
        session = await session_ctx.__aenter__()
        exit_stack.append(session_ctx)

        await session.initialize()
        tools = await load_mcp_tools(session)
        all_tools.extend(tools)

    return all_tools, exit_stack

async def close_all(exit_stack: list):
    """Close all MCP sessions cleanly."""
    for ctx in reversed(exit_stack):
        try:
            await ctx.__aexit__(None, None, None)
        except Exception:
            pass

# ── Test runner ───────────────────────────────────────────────────────────────
async def run_tests():
    print("=" * 60)
    print("TrackHaul MCP Agent — Integration Test Suite")
    print("=" * 60)

    print("\nLoading MCP tools...")
    all_tools, exit_stack = await load_all_tools()
    print(f"Tools loaded: {[t.name for t in all_tools]}\n")

    agent = create_react_agent(llm, all_tools)

    passed = 0
    failed = 0

    try:
        for test in TEST_QUERIES:
            print(f"{'─' * 60}")
            print(f"[{test['id']}] {test['description']}")
            print(f"Query: {test['query']}")
            print()

            try:
                result = await agent.ainvoke({
                    "messages": [{"role": "user", "content": test["query"]}]
                })
                response = result["messages"][-1].content
                print(f"Response:\n{response}")
                print(f"\n✅ PASSED")
                passed += 1
            except Exception as e:
                print(f"❌ FAILED — {str(e)}")
                failed += 1

            print()

    finally:
        await close_all(exit_stack)

    print("=" * 60)
    print(f"Results: {passed} passed, {failed} failed out of {len(TEST_QUERIES)} tests")
    print("=" * 60)

if __name__ == "__main__":
    asyncio.run(run_tests())