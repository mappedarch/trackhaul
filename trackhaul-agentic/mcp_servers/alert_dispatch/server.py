"""
TrackHaul MCP Server — Alert Dispatch
Exposes alert dispatching as MCP tools.
No PII in alert payloads — truck IDs only.
"""

from mcp.server.fastmcp import FastMCP
from mcp_servers.alert_dispatch.mock_data import dispatch_alert, get_alert_log

mcp = FastMCP("trackhaul-alert-dispatch")

@mcp.tool()
def send_alert(truck_id: str, severity: str, message: str) -> dict:
    """
    Dispatch an operational alert for a truck.
    Severity must be one of: low, medium, high, critical.
    """
    valid_severities = {"low", "medium", "high", "critical"}
    if severity not in valid_severities:
        return {"error": f"Invalid severity '{severity}'. Must be one of {valid_severities}"}
    return dispatch_alert(truck_id, severity, message)

@mcp.tool()
def get_dispatched_alerts() -> list:
    """Return all alerts dispatched in this session."""
    return get_alert_log()

if __name__ == "__main__":
    import asyncio
    asyncio.run(mcp.run_stdio_async())