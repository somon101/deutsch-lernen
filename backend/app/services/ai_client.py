"""DeepSeek chat client (§ AI lesson generator, 2026-10-03).

DeepSeek's API is OpenAI-compatible: one POST to /chat/completions. JSON
mode (`response_format: json_object`) makes the model return a single JSON
object, which is all the lesson generator ever asks for."""

import json

import httpx

from app.config import settings
from app.errors import ApiError


async def chat_json(api_key: str, model: str, system: str, user: str, *, max_tokens: int = 8000) -> dict:
    """Returns the model's reply parsed as a JSON object. Retries once when
    the reply is not valid JSON; provider errors surface as ApiError(502)
    carrying the provider's own message, so the admin sees what went wrong
    (bad key, no balance, ...)."""
    payload = {
        "model": model,
        "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
        "response_format": {"type": "json_object"},
        "temperature": 0.4,
        "max_tokens": max_tokens,
    }
    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
    last_error = "пустой ответ"
    async with httpx.AsyncClient(timeout=240.0) as client:
        for _ in range(2):
            try:
                response = await client.post(settings.deepseek_url, json=payload, headers=headers)
            except httpx.HTTPError as e:
                raise ApiError(502, f"Не удалось связаться с DeepSeek: {e}") from e
            if response.status_code != 200:
                try:
                    message = response.json().get("error", {}).get("message") or response.text
                except ValueError:
                    message = response.text
                raise ApiError(502, f"DeepSeek ответил ошибкой ({response.status_code}): {message[:300]}")
            try:
                content = response.json()["choices"][0]["message"]["content"]
                parsed = json.loads(content)
                if isinstance(parsed, dict):
                    return parsed
                last_error = "ответ не является JSON-объектом"
            except (KeyError, IndexError, ValueError) as e:
                last_error = str(e)
    raise ApiError(502, f"ИИ вернул некорректный ответ: {last_error}")
