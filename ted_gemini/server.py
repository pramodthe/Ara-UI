from __future__ import annotations

import base64
import os
from pathlib import Path
from typing import Any

import requests
from fastapi import HTTPException
from fastapi.responses import Response
from google.adk.cli.fast_api import get_fast_api_app
from pydantic import BaseModel


REPO_ROOT = Path(__file__).resolve().parents[1]
AGENTS_DIR = REPO_ROOT / "ted_gemini" / "app"


def load_root_env() -> None:
    env_path = REPO_ROOT / ".env"
    if not env_path.exists():
        return

    for raw_line in env_path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


load_root_env()

app = get_fast_api_app(
    agents_dir=str(AGENTS_DIR),
    web=False,
    host="127.0.0.1",
    port=8000,
    allow_origins=["*"],
)


class ImageGenerationRequest(BaseModel):
    prompt: str
    image_data: str
    mime_type: str = "image/png"


class TextToSpeechRequest(BaseModel):
    text: str
    voice: str = "Cherry"
    language_type: str = "English"


def dashscope_key() -> str:
    api_key = os.getenv("DASHSCOPE_API_KEY", "").strip()
    if not api_key:
        raise HTTPException(status_code=500, detail="DASHSCOPE_API_KEY is not configured")
    return api_key


def dashscope_api_url() -> str:
    return os.getenv(
        "DASHSCOPE_API_URL",
        "https://dashscope-intl.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation",
    )


def dashscope_headers() -> dict[str, str]:
    return {
        "Authorization": f"Bearer {dashscope_key()}",
        "Content-Type": "application/json",
    }


def post_dashscope(payload: dict[str, Any]) -> dict[str, Any]:
    try:
        response = requests.post(
            dashscope_api_url(),
            headers=dashscope_headers(),
            json=payload,
            timeout=120,
        )
    except requests.RequestException as exc:
        raise HTTPException(status_code=502, detail=f"DashScope request failed: {exc}") from exc

    if response.status_code >= 400:
        raise HTTPException(status_code=response.status_code, detail=response.text)

    try:
        return response.json()
    except ValueError as exc:
        raise HTTPException(status_code=502, detail="DashScope returned invalid JSON") from exc


def first_nested_value(value: Any, keys: set[str]) -> str | None:
    if isinstance(value, dict):
        for key, item in value.items():
            if key in keys and isinstance(item, str) and item:
                return item
        for item in value.values():
            found = first_nested_value(item, keys)
            if found:
                return found
    elif isinstance(value, list):
        for item in value:
            found = first_nested_value(item, keys)
            if found:
                return found
    return None


def fetch_binary_url(url: str) -> tuple[bytes, str]:
    try:
        response = requests.get(url, timeout=120)
    except requests.RequestException as exc:
        raise HTTPException(status_code=502, detail=f"Failed to download DashScope asset: {exc}") from exc

    if response.status_code >= 400:
        raise HTTPException(status_code=response.status_code, detail="DashScope asset download failed")

    content_type = response.headers.get("content-type", "application/octet-stream")
    return response.content, content_type


@app.post("/araui/image-generation")
def generate_image(request: ImageGenerationRequest) -> Response:
    prompt = request.prompt.strip()
    if not prompt:
        raise HTTPException(status_code=400, detail="Prompt is required")
    if not request.image_data:
        raise HTTPException(status_code=400, detail="image_data is required")

    image_url = f"data:{request.mime_type};base64,{request.image_data}"
    payload = {
        "model": os.getenv("DASHSCOPE_IMAGE_MODEL", "qwen-image-2.0-pro"),
        "input": {
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"image": image_url},
                        {"text": prompt},
                    ],
                }
            ]
        },
        "parameters": {
            "n": 1,
            "size": os.getenv("DASHSCOPE_IMAGE_SIZE", "1024*1024"),
        },
    }

    result = post_dashscope(payload)
    image_base64 = first_nested_value(result, {"data", "b64_json", "base64"})
    if image_base64:
        try:
            return Response(content=base64.b64decode(image_base64), media_type="image/png")
        except ValueError as exc:
            raise HTTPException(status_code=502, detail="DashScope returned invalid image data") from exc

    image_asset_url = first_nested_value(result, {"image", "url"})
    if image_asset_url:
        data, content_type = fetch_binary_url(image_asset_url)
        return Response(content=data, media_type=content_type)

    raise HTTPException(status_code=502, detail="DashScope response did not include an image")


@app.post("/araui/tts")
def synthesize_speech(request: TextToSpeechRequest) -> Response:
    text = request.text.strip()
    if not text:
        raise HTTPException(status_code=400, detail="Text is required")

    payload = {
        "model": os.getenv("DASHSCOPE_TTS_MODEL", "qwen3-tts-flash"),
        "input": {
            "text": text[:600],
            "voice": request.voice,
            "language_type": request.language_type,
        },
        "parameters": {
            "response_format": "mp3",
            "sample_rate": 24000,
        },
    }

    result = post_dashscope(payload)
    audio_base64 = first_nested_value(result, {"data", "audio_data", "base64"})
    if audio_base64:
        try:
            return Response(content=base64.b64decode(audio_base64), media_type="audio/mpeg")
        except ValueError as exc:
            raise HTTPException(status_code=502, detail="DashScope returned invalid audio data") from exc

    audio_url = first_nested_value(result, {"url"})
    if audio_url:
        data, content_type = fetch_binary_url(audio_url)
        return Response(content=data, media_type=content_type)

    raise HTTPException(status_code=502, detail="DashScope response did not include audio")
