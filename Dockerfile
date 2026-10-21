# Python Backend for OncoVault (AI Diagnostic Models + Whisper + Clinical NLP)
FROM python:3.10-slim

WORKDIR /app

# Install system dependencies for audio decoding (ffmpeg) and git
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python requirements
COPY requirements-backend.txt .
RUN pip install --no-cache-dir -r requirements-backend.txt

# Download spaCy English model for biomedical concept processing
RUN python -m spacy download en_core_web_sm || true

# Copy backend source code
COPY oncovault_nlp/ ./oncovault_nlp/
COPY oncovault_ai/ ./oncovault_ai/

# Add directories to Python path
ENV PYTHONPATH="/app/oncovault_nlp:/app"
ENV PORT=8000

EXPOSE 8000

# Run FastAPI via Uvicorn
CMD ["sh", "-c", "uvicorn oncovault_nlp.main:app --host 0.0.0.0 --port ${PORT}"]
