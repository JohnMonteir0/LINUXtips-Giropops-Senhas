# ---------- Build ----------
FROM cgr.dev/chainguard/python:latest-dev AS build

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    VIRTUAL_ENV=/home/nonroot/venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

WORKDIR /app

# Create venv and install deps
RUN python -m venv "$VIRTUAL_ENV" \
 && python -m pip install --no-cache-dir --upgrade pip setuptools wheel

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy your app
COPY . .

# ---------- Runtime ----------
FROM cgr.dev/chainguard/python:latest

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    VIRTUAL_ENV=/home/nonroot/venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

WORKDIR /app

# Bring over the prebuilt venv and your app
COPY --from=build $VIRTUAL_ENV $VIRTUAL_ENV
COPY . .

# Optional: declare port (helps docs/tools)
EXPOSE 5000

# --- Option A: Gunicorn (recommended for prod) ---
# Requires your app to expose "app" (Flask) in app.py or wsgi.py
# CMD ["gunicorn", "-w", "2", "-b", "0.0.0.0:5000", "app:app"]

# --- Option B: Plain Python (fine for labs/dev) ---
CMD ["python", "/app/app.py"]
