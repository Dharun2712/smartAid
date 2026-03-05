"""
SmartAid Accident Image Analysis Module
Uses Groq Vision API (LLaVA v1.5) to analyze accident scene images.

Workflow:
  1. User uploads accident image
  2. Image is base64-encoded and sent to Groq Vision Model
  3. AI extracts accident features (people, vehicles, injuries, fire, damage)
  4. Severity level predicted
  5. Ambulance alert priority returned
"""

import os
import base64
import json
import re
import logging
from typing import Optional

logger = logging.getLogger(__name__)

# Groq API key – MUST be set via environment variable
GROQ_API_KEY = os.environ.get(
    "GROQ_API_KEY",
    "",  # Set GROQ_API_KEY environment variable before running
)

if not GROQ_API_KEY:
    logger.warning(
        "⚠️  GROQ_API_KEY not set. Image analysis will fail. "
        "Set the GROQ_API_KEY environment variable."
    )

# Vision model available on Groq
VISION_MODEL = "llava-v1.5-7b-4096-preview"

# System prompt sent to the vision model
ANALYSIS_PROMPT = """You are an AI emergency accident analysis system used in a SmartAid platform.

Analyze the uploaded accident scene image carefully and estimate the severity of the accident.

Your tasks:

1. Count the number of people visible in the accident scene.
2. Count the number of vehicles involved (car, truck, bike, bus).
3. Detect if there is any fire, smoke, or explosion risk.
4. Identify possible injured persons (lying on ground, unconscious posture, severe damage).
5. Estimate the vehicle damage level from 1 to 5:
   1 = very minor
   2 = minor
   3 = moderate
   4 = severe
   5 = catastrophic

6. Estimate the overall accident severity level:
   - LOW
   - MEDIUM
   - CRITICAL

Severity rules:
LOW → minor damage, few people, no fire
MEDIUM → multiple vehicles or injured persons
CRITICAL → major crash, fire, multiple injured people

Return ONLY a valid JSON response with this structure:

{
  "people_detected": number,
  "vehicles_detected": number,
  "possible_injured": number,
  "fire_detected": true/false,
  "damage_level": number,
  "severity_level": "LOW | MEDIUM | CRITICAL",
  "ambulance_priority": "LOW | MEDIUM | HIGH"
}

Do not include explanations. Only return JSON."""


def _get_groq_client():
    """Lazily import and build the Groq client."""
    try:
        from groq import Groq
        return Groq(api_key=GROQ_API_KEY)
    except ImportError:
        raise RuntimeError(
            "The 'groq' package is not installed. "
            "Install it with: pip install groq"
        )


def _extract_json(text: str) -> dict:
    """
    Extract the first JSON object from a model response that might
    contain markdown fences or extra text around it.
    """
    # Try direct parse first
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass

    # Try to find JSON block in markdown fences
    md_match = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL)
    if md_match:
        return json.loads(md_match.group(1))

    # Try to find first { ... } block
    brace_match = re.search(r"\{.*\}", text, re.DOTALL)
    if brace_match:
        return json.loads(brace_match.group(0))

    raise ValueError(f"Could not extract JSON from model response: {text[:200]}")


def _validate_result(data: dict) -> dict:
    """Validate and normalise the AI response into the expected schema."""
    result = {
        "people_detected": int(data.get("people_detected", 0)),
        "vehicles_detected": int(data.get("vehicles_detected", 0)),
        "possible_injured": int(data.get("possible_injured", 0)),
        "fire_detected": bool(data.get("fire_detected", False)),
        "damage_level": max(1, min(5, int(data.get("damage_level", 1)))),
        "severity_level": str(data.get("severity_level", "LOW")).upper(),
        "ambulance_priority": str(data.get("ambulance_priority", "LOW")).upper(),
    }

    # Clamp severity to valid values
    if result["severity_level"] not in ("LOW", "MEDIUM", "CRITICAL"):
        result["severity_level"] = "MEDIUM"
    if result["ambulance_priority"] not in ("LOW", "MEDIUM", "HIGH"):
        result["ambulance_priority"] = "MEDIUM"

    return result


def analyze_accident_image(image_bytes: bytes, mime_type: str = "image/jpeg") -> dict:
    """
    Analyze an accident scene image using the Groq Vision API.

    Parameters
    ----------
    image_bytes : bytes
        Raw bytes of the image file (JPEG / PNG).
    mime_type : str
        MIME type of the image, e.g. "image/jpeg" or "image/png".

    Returns
    -------
    dict
        A dict with keys: people_detected, vehicles_detected,
        possible_injured, fire_detected, damage_level,
        severity_level, ambulance_priority.
    """
    logger.info("🔍 Starting accident image analysis via Groq Vision API ...")

    client = _get_groq_client()

    # Base64 encode the image
    b64_data = base64.b64encode(image_bytes).decode("utf-8")
    data_uri = f"data:{mime_type};base64,{b64_data}"

    # Call Groq Vision API
    response = client.chat.completions.create(
        model=VISION_MODEL,
        messages=[
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": ANALYSIS_PROMPT},
                    {
                        "type": "image_url",
                        "image_url": {"url": data_uri},
                    },
                ],
            }
        ],
        temperature=0.1,   # Low temperature for consistent structured output
        max_tokens=512,
    )

    raw_text = response.choices[0].message.content
    logger.info(f"📝 Raw model response: {raw_text[:300]}")

    parsed = _extract_json(raw_text)
    result = _validate_result(parsed)

    logger.info(f"✅ Analysis complete — severity={result['severity_level']}, priority={result['ambulance_priority']}")
    return result


def analyze_accident_image_from_file(file_path: str) -> dict:
    """Convenience wrapper that reads a file from disk and analyses it."""
    import mimetypes

    mime, _ = mimetypes.guess_type(file_path)
    if mime is None:
        mime = "image/jpeg"

    with open(file_path, "rb") as f:
        return analyze_accident_image(f.read(), mime_type=mime)
