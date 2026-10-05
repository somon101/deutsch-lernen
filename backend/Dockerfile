FROM python:3.12-slim

WORKDIR /app

# ffmpeg decodes uploaded mp3/m4a/ogg/webm for the video constructor's
# speech analysis (services/speech_timeline.py).
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

ENV PORT=8080
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"]
