"""
TrackHaul MCP Client — LangGraph Agent
Connects to all three MCP servers via stdio transport.
Sessions are kept alive for the duration of the agent run.
"""

import asyncio
import sys
import os
from langchain_aws import ChatBedrockConverse
from langgraph.prebuilt import create_react_agent
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from langchain_mcp_adapters.tools import load_mcp_tools

# ── Bedrock LLM ──────────────────────────────────────────────────────────────
llm = ChatBedrockConverse(
    model="eu.anthropic.claude-sonnet-4-5-20250929-v1:0",
    region_name="eu-west-1",
)

# ── MCP Server definitions ────────────────────────────────────────────────────
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

# ── Main agent runner ─────────────────────────────────────────────────────────
async def run_agent(query: str):
    """
    Open all MCP server sessions, keep them alive,
    load tools, run agent, then close sessions.
    """
    all_tools = []
    # Stack of context managers kept open for agent lifetime
    exit_stack = []

    try:
        for name, params in SERVERS.items():
            # Open stdio transport — must stay open
            stdio_ctx = stdio_client(params)
            read, write = await stdio_ctx.__aenter__()
            exit_stack.append(stdio_ctx)

            # Open MCP session — must stay open
            session_ctx = ClientSession(read, write)
            session = await session_ctx.__aenter__()
            exit_stack.append(session_ctx)

            await session.initialize()
            tools = await load_mcp_tools(session)
            print(f"  [{name}] loaded {len(tools)} tools: {[t.name for t in tools]}")
            all_tools.extend(tools)

        print(f"\nTotal tools loaded: {len(all_tools)}")
        print(f"Query: {query}\n")

        agent = create_react_agent(llm, all_tools)
        result = await agent.ainvoke({
            "messages": [{"role": "user", "content": query}]
        })

        print("Response:")
        print(result["messages"][-1].content)

    finally:
        # Close all sessions in reverse order
        for ctx in reversed(exit_stack):
            try:
                await ctx.__aexit__(None, None, None)
            except Exception:
                pass

if __name__ == "__main__":
    query = "Which trucks have open faults? For each one, check their current status and dispatch a high severity alert."
    asyncio.run(run_agent(query))