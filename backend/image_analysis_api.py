"""
Accident Image Analysis API Router
Integrates with app_fastapi.py — provides endpoint for uploading
accident scene images and receiving AI-powered severity analysis.
"""

import logging
import time
from fastapi import APIRouter, HTTPException, UploadFile, File, Form
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from typing import Optional

logger = logging.getLogger(__name__)

# Create router
image_analysis_router = APIRouter(
    prefix="/api/accident-image",
    tags=["Accident Image Analysis"],
)

# Maximum file size: 10 MB
MAX_FILE_SIZE = 10 * 1024 * 1024
ALLOWED_MIME_TYPES = {"image/jpeg", "image/png", "image/jpg", "image/webp"}


@image_analysis_router.post("/analyze")
async def analyze_accident(
    file: UploadFile = File(..., description="Accident scene image (JPEG/PNG)"),
    lat: Optional[float] = Form(None, description="Latitude of accident location"),
    lng: Optional[float] = Form(None, description="Longitude of accident location"),
):
    """
    🚑 Analyze an accident scene image using AI Vision Model (Groq + LLaVA)

    Upload an image of an accident scene and receive:
    - Number of people detected
    - Number of vehicles involved
    - Number of possible injured persons
    - Fire / explosion detection
    - Damage level (1-5)
    - Severity level (LOW / MEDIUM / CRITICAL)
    - Ambulance priority (LOW / MEDIUM / HIGH)

    Supported formats: JPEG, PNG, WebP
    Max file size: 10 MB
    """
    start_time = time.time()

    # Validate content type
    content_type = file.content_type or "image/jpeg"
    if content_type not in ALLOWED_MIME_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file type: {content_type}. Allowed: {', '.join(ALLOWED_MIME_TYPES)}",
        )

    # Read file bytes
    image_bytes = await file.read()

    # Validate file size
    if len(image_bytes) > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=400,
            detail=f"File too large ({len(image_bytes)} bytes). Maximum is {MAX_FILE_SIZE} bytes (10 MB).",
        )

    if len(image_bytes) == 0:
        raise HTTPException(status_code=400, detail="Uploaded file is empty.")

    logger.info(
        f"📸 Received accident image: {file.filename} | "
        f"Size: {len(image_bytes)} bytes | Type: {content_type}"
    )

    # Run AI analysis
    try:
        from accident_image_analyzer import analyze_accident_image

        result = analyze_accident_image(image_bytes, mime_type=content_type)
    except RuntimeError as e:
        logger.error(f"❌ Groq SDK error: {e}")
        raise HTTPException(status_code=503, detail=str(e))
    except Exception as e:
        logger.error(f"❌ Image analysis failed: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Image analysis failed: {str(e)}",
        )

    elapsed_ms = (time.time() - start_time) * 1000

    # Build response
    response = {
        "success": True,
        "analysis": result,
        "metadata": {
            "filename": file.filename,
            "file_size_bytes": len(image_bytes),
            "content_type": content_type,
            "processing_time_ms": round(elapsed_ms, 2),
        },
    }

    # Attach location if provided
    if lat is not None and lng is not None:
        response["location"] = {"lat": lat, "lng": lng}

    logger.info(
        f"✅ Analysis complete in {elapsed_ms:.0f}ms — "
        f"severity={result['severity_level']}, priority={result['ambulance_priority']}"
    )

    return response


@image_analysis_router.get("/health")
async def image_analysis_health():
    """Health check for the image analysis service"""
    try:
        from accident_image_analyzer import GROQ_API_KEY, VISION_MODEL

        has_key = bool(GROQ_API_KEY and len(GROQ_API_KEY) > 10)
        return {
            "success": True,
            "service": "accident-image-analysis",
            "status": "ready" if has_key else "no_api_key",
            "model": VISION_MODEL,
            "max_file_size_mb": MAX_FILE_SIZE // (1024 * 1024),
            "supported_formats": list(ALLOWED_MIME_TYPES),
        }
    except Exception as e:
        return {
            "success": False,
            "service": "accident-image-analysis",
            "status": "error",
            "detail": str(e),
        }


# Export
__all__ = ["image_analysis_router"]
