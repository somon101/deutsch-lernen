FROM python:3.12-slim

WORKDIR /app

# ffmpeg decodes uploaded mp3/m4a/ogg/webm for the video constructor's
# speech analysis (services/speech_timeline.py).
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Rhubarb Lip Sync: phoneme-based mouth shapes for the video constructor
# (services/speech_timeline.py reads RHUBARB_PATH).
ADD https://github.com/DanielSWolf/rhubarb-lip-sync/releases/download/v1.14.0/Rhubarb-Lip-Sync-1.14.0-Linux.zip /tmp/rhubarb.zip
RUN python -c "import zipfile, os; z = zipfile.ZipFile('/tmp/rhubarb.zip'); z.extractall('/opt'); os.rename('/opt/' + z.namelist()[0].split('/')[0], '/opt/rhubarb')"     && chmod +x /opt/rhubarb/rhubarb     && rm /tmp/rhubarb.zip
ENV RHUBARB_PATH=/opt/rhubarb/rhubarb

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

ENV PORT=8080
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"]
