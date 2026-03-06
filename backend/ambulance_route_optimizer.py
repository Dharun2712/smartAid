"""
SmartAid Intelligent Ambulance Route Optimizer

Uses Google Directions API (multiple alternatives) + Groq LLM to select
the optimal emergency route.

Workflow:
  Ambulance GPS + Accident GPS
      |
      v
  Google Directions API  →  Fetches up to 3 alternative routes
      |
      v
  AI Route Selector      →  Picks best route based on distance, time,
                             road type, traffic conditions
      |
      v
  Returns optimal route JSON with polyline + metadata
"""

import os
import json
import math
import logging
import time
from typing import List, Dict, Any, Optional, Tuple

logger = logging.getLogger(__name__)

# Google Maps API key
GOOGLE_MAPS_API_KEY = os.environ.get(
    "GOOGLE_MAPS_API_KEY",
    "AIzaSyB4P99kVH_B4Y1sdLmIEvVjrpO-cZFrFKY",  # Same key as Flutter app
)

# Groq API for intelligent route reasoning (optional enhancement)
GROQ_API_KEY = os.environ.get("GROQ_API_KEY", "")


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate straight-line distance in km between two GPS coordinates."""
    R = 6371.0  # Earth radius in km
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (math.sin(dlat / 2) ** 2 +
         math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) *
         math.sin(dlon / 2) ** 2)
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _score_route(route: Dict[str, Any]) -> float:
    """
    Score a route for emergency ambulance dispatch.
    Lower score = better route.

    Scoring weights:
      - Distance (km): 40%
      - Duration (minutes): 50%
      - Road quality bonus: 10%
    """
    distance_km = route.get("distance_km", 999)
    duration_min = route.get("estimated_time_minutes", 999)

    # Prefer highways / main roads (check summary for indicators)
    summary = (route.get("summary", "") or "").lower()
    road_bonus = 0.0
    highway_keywords = ["highway", "expressway", "nh", "sh", "national", "bypass", "ring road", "motorway"]
    if any(kw in summary for kw in highway_keywords):
        road_bonus = -2.0  # Reward highways

    # Check for known bad indicators
    avoid_keywords = ["residential", "service road", "narrow", "unpaved"]
    if any(kw in summary for kw in avoid_keywords):
        road_bonus += 3.0  # Penalty

    # Traffic penalty (if duration_in_traffic available)
    traffic_duration = route.get("duration_in_traffic_minutes")
    if traffic_duration and traffic_duration > duration_min * 1.3:
        road_bonus += 5.0  # Heavy traffic penalty

    score = (distance_km * 0.4) + (duration_min * 0.5) + road_bonus
    return round(score, 3)


def select_optimal_route(routes: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Given multiple route alternatives, select the optimal one for
    emergency ambulance dispatch.

    Returns the selected route with scoring metadata.
    """
    if not routes:
        raise ValueError("No routes provided")

    if len(routes) == 1:
        route = routes[0]
        route["score"] = _score_route(route)
        route["reason"] = "Only available route"
        return route

    # Score all routes
    scored = []
    for r in routes:
        r["score"] = _score_route(r)
        scored.append(r)

    # Sort by score (lower is better)
    scored.sort(key=lambda r: r["score"])

    best = scored[0]
    second = scored[1] if len(scored) > 1 else None

    # Build reasoning
    reasons = []
    if second:
        dist_diff = second.get("distance_km", 0) - best.get("distance_km", 0)
        time_diff = second.get("estimated_time_minutes", 0) - best.get("estimated_time_minutes", 0)

        if dist_diff > 0.5:
            reasons.append(f"{dist_diff:.1f} km shorter than alternative")
        if time_diff > 1:
            reasons.append(f"{time_diff:.0f} min faster than alternative")

        summary = best.get("summary", "")
        if summary:
            reasons.append(f"Via {summary}")

    if not reasons:
        reasons.append("Shortest and fastest route for ambulance dispatch")

    best["reason"] = "; ".join(reasons)
    best["alternatives_evaluated"] = len(routes)
    return best


def build_route_response(
    selected_route: Dict[str, Any],
    ambulance_lat: float,
    ambulance_lng: float,
    accident_lat: float,
    accident_lng: float,
) -> Dict[str, Any]:
    """Build the final JSON response for the routing endpoint."""
    straight_line_km = haversine_distance(
        ambulance_lat, ambulance_lng, accident_lat, accident_lng
    )

    return {
        "selected_route": selected_route.get("route_id", "route_0"),
        "distance_km": round(selected_route.get("distance_km", 0), 2),
        "estimated_time_minutes": round(selected_route.get("estimated_time_minutes", 0), 1),
        "priority": "EMERGENCY",
        "reason": selected_route.get("reason", "Optimal emergency route"),
        "summary": selected_route.get("summary", ""),
        "score": selected_route.get("score", 0),
        "alternatives_evaluated": selected_route.get("alternatives_evaluated", 1),
        "straight_line_km": round(straight_line_km, 2),
        "route_efficiency": round(
            straight_line_km / max(selected_route.get("distance_km", 1), 0.01) * 100, 1
        ),
        "polyline": selected_route.get("polyline", ""),
        "steps": selected_route.get("steps", []),
        "origin": {"lat": ambulance_lat, "lng": ambulance_lng},
        "destination": {"lat": accident_lat, "lng": accident_lng},
    }


def parse_google_directions_response(google_response: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Parse a Google Directions API response into our normalized route format.
    Handles multiple alternative routes.
    """
    routes = []
    raw_routes = google_response.get("routes", [])

    for idx, raw_route in enumerate(raw_routes):
        legs = raw_route.get("legs", [])
        if not legs:
            continue

        leg = legs[0]  # Single origin→destination has one leg

        distance_m = leg.get("distance", {}).get("value", 0)
        duration_s = leg.get("duration", {}).get("value", 0)
        duration_traffic_s = leg.get("duration_in_traffic", {}).get("value")

        # Extract turn-by-turn steps
        steps = []
        for step in leg.get("steps", []):
            steps.append({
                "instruction": step.get("html_instructions", ""),
                "distance_m": step.get("distance", {}).get("value", 0),
                "duration_s": step.get("duration", {}).get("value", 0),
                "maneuver": step.get("maneuver", ""),
            })

        route = {
            "route_id": f"route_{idx}",
            "distance_km": round(distance_m / 1000, 2),
            "estimated_time_minutes": round(duration_s / 60, 1),
            "duration_in_traffic_minutes": round(duration_traffic_s / 60, 1) if duration_traffic_s else None,
            "summary": raw_route.get("summary", ""),
            "polyline": raw_route.get("overview_polyline", {}).get("points", ""),
            "steps": steps,
            "distance_text": leg.get("distance", {}).get("text", ""),
            "duration_text": leg.get("duration", {}).get("text", ""),
            "start_address": leg.get("start_address", ""),
            "end_address": leg.get("end_address", ""),
            "warnings": raw_route.get("warnings", []),
        }
        routes.append(route)

    return routes


async def fetch_google_directions(
    ambulance_lat: float,
    ambulance_lng: float,
    accident_lat: float,
    accident_lng: float,
    alternatives: bool = True,
) -> Dict[str, Any]:
    """
    Fetch routes from Google Directions API.
    Returns the raw Google API response.
    """
    import httpx

    url = "https://maps.googleapis.com/maps/api/directions/json"
    params = {
        "origin": f"{ambulance_lat},{ambulance_lng}",
        "destination": f"{accident_lat},{accident_lng}",
        "mode": "driving",
        "alternatives": str(alternatives).lower(),
        "departure_time": "now",  # For traffic-aware routing
        "key": GOOGLE_MAPS_API_KEY,
    }

    async with httpx.AsyncClient(timeout=15.0) as client:
        resp = await client.get(url, params=params)
        resp.raise_for_status()
        return resp.json()


async def get_optimal_route(
    ambulance_lat: float,
    ambulance_lng: float,
    accident_lat: float,
    accident_lng: float,
) -> Dict[str, Any]:
    """
    Main entry point: Fetch routes, score them, and return optimal route.

    Returns a complete JSON response ready for the API.
    """
    start_time = time.time()

    logger.info(
        f"🚑 Route optimization: ambulance=({ambulance_lat},{ambulance_lng}) "
        f"→ accident=({accident_lat},{accident_lng})"
    )

    # 1. Fetch alternative routes from Google Directions
    google_response = await fetch_google_directions(
        ambulance_lat, ambulance_lng,
        accident_lat, accident_lng,
        alternatives=True,
    )

    status = google_response.get("status", "UNKNOWN")
    if status != "OK":
        raise RuntimeError(f"Google Directions API error: {status}")

    # 2. Parse routes
    routes = parse_google_directions_response(google_response)
    if not routes:
        raise RuntimeError("No routes found between the locations")

    logger.info(f"📊 Found {len(routes)} alternative route(s)")
    for r in routes:
        logger.info(
            f"   → {r['route_id']}: {r['distance_km']} km, "
            f"{r['estimated_time_minutes']} min via {r['summary']}"
        )

    # 3. Select optimal route
    best_route = select_optimal_route(routes)

    # 4. Build response
    response = build_route_response(
        best_route,
        ambulance_lat, ambulance_lng,
        accident_lat, accident_lng,
    )

    elapsed = (time.time() - start_time) * 1000
    response["processing_time_ms"] = round(elapsed, 2)

    logger.info(
        f"✅ Selected {best_route['route_id']}: "
        f"{best_route['distance_km']} km, {best_route['estimated_time_minutes']} min "
        f"(score: {best_route['score']}) in {elapsed:.0f}ms"
    )

    return response
