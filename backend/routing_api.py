"""
Ambulance Routing API Router
Integrates with app_fastapi.py — provides intelligent emergency
route optimization using Google Directions + AI scoring.
"""

import logging
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field
from typing import Optional

logger = logging.getLogger(__name__)

routing_router = APIRouter(
    prefix="/api/routing",
    tags=["Ambulance Routing"],
)


class RouteRequest(BaseModel):
    ambulance_lat: float = Field(..., ge=-90, le=90, description="Ambulance latitude")
    ambulance_lng: float = Field(..., ge=-180, le=180, description="Ambulance longitude")
    accident_lat: float = Field(..., ge=-90, le=90, description="Accident latitude")
    accident_lng: float = Field(..., ge=-180, le=180, description="Accident longitude")


class RouteToHospitalRequest(BaseModel):
    current_lat: float = Field(..., ge=-90, le=90)
    current_lng: float = Field(..., ge=-180, le=180)
    hospital_lat: float = Field(..., ge=-90, le=90)
    hospital_lng: float = Field(..., ge=-180, le=180)
    patient_onboard: bool = Field(True, description="Is patient already picked up?")


@routing_router.post("/optimal-route")
async def get_optimal_route(request: RouteRequest):
    """
    🚑 Get the optimal emergency route from ambulance to accident location.

    Fetches multiple alternative routes from Google Directions API,
    then uses AI scoring to select the best one based on:
    - Shortest distance
    - Fastest travel time
    - Road quality (highways preferred)
    - Traffic conditions

    Returns the selected route with polyline, distance, ETA, and reasoning.
    """
    try:
        from ambulance_route_optimizer import get_optimal_route as optimize

        result = await optimize(
            ambulance_lat=request.ambulance_lat,
            ambulance_lng=request.ambulance_lng,
            accident_lat=request.accident_lat,
            accident_lng=request.accident_lng,
        )

        return {
            "success": True,
            "route": result,
        }

    except RuntimeError as e:
        logger.error(f"❌ Routing error: {e}")
        raise HTTPException(status_code=502, detail=str(e))
    except Exception as e:
        logger.error(f"❌ Route optimization failed: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Route optimization failed: {str(e)}",
        )


@routing_router.post("/route-to-hospital")
async def get_route_to_hospital(request: RouteToHospitalRequest):
    """
    🏥 Get optimal route from current location to hospital.
    Used after patient pickup for the second leg of the journey.
    """
    try:
        from ambulance_route_optimizer import get_optimal_route as optimize

        result = await optimize(
            ambulance_lat=request.current_lat,
            ambulance_lng=request.current_lng,
            accident_lat=request.hospital_lat,
            accident_lng=request.hospital_lng,
        )

        result["priority"] = "EMERGENCY" if request.patient_onboard else "HIGH"
        result["leg"] = "to_hospital"

        return {
            "success": True,
            "route": result,
        }

    except Exception as e:
        logger.error(f"❌ Hospital routing failed: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Hospital routing failed: {str(e)}",
        )


@routing_router.get("/health")
async def routing_health():
    """Health check for the routing service."""
    from ambulance_route_optimizer import GOOGLE_MAPS_API_KEY

    has_key = bool(GOOGLE_MAPS_API_KEY and len(GOOGLE_MAPS_API_KEY) > 10)
    return {
        "success": True,
        "service": "ambulance-routing",
        "status": "ready" if has_key else "no_api_key",
    }


__all__ = ["routing_router"]
