"""
TrackHaul MCP Server — Maintenance Lookup
Exposes maintenance history and open faults as MCP tools.
No PII returned — truck IDs only.
"""

from mcp.server.fastmcp import FastMCP
from mcp_servers.maintenance.mock_data import get_maintenance_history, get_open_faults

mcp = FastMCP("trackhaul-maintenance")

@mcp.tool()
def get_truck_maintenance_history(truck_id: str) -> list:
    """Get full maintenance history for a truck."""
    results = get_maintenance_history(truck_id)
    return results if results else [{"message": f"No maintenance records for {truck_id}"}]

@mcp.tool()
def get_truck_open_faults(truck_id: str) -> list:
    """Get all open (unresolved) maintenance faults for a truck."""
    results = get_open_faults(truck_id)
    return results if results else [{"message": f"No open faults for {truck_id}"}]

if __name__ == "__main__":
    mcp.run(transport="stdio")