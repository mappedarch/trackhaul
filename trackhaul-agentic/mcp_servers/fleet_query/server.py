"""
TrackHaul MCP Server — Fleet Query
Exposes fleet vehicle status as MCP tools.
No PII returned — truck IDs only.
"""

from mcp.server.fastmcp import FastMCP
from mcp_servers.fleet_query.mock_data import get_vehicle, filter_by_status, filter_by_region

mcp = FastMCP("trackhaul-fleet-query")

@mcp.tool()
def get_vehicle_status(truck_id: str) -> dict:
    """Get current status of a specific truck by ID."""
    result = get_vehicle(truck_id)
    if not result:
        return {"error": f"Truck {truck_id} not found"}
    return result

@mcp.tool()
def list_vehicles_by_status(status: str) -> list:
    """List all trucks matching a given status: active, fault, or idle."""
    results = filter_by_status(status)
    return results if results else [{"message": f"No trucks with status '{status}'"}]

@mcp.tool()
def list_vehicles_by_region(region: str) -> list:
    """List all trucks operating in a given region: DE, PL, or NL."""
    results = filter_by_region(region)
    return results if results else [{"message": f"No trucks in region '{region}'"}]

if __name__ == "__main__":
    mcp.run(transport="stdio")