# ---------- Build ----------
FROM cgr.dev/chainguard/python:latest-dev AS build

# Chainguard runs as non-root; create venv somewhere writable
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

# Bring in the app source
COPY . .

# ---------- Runtime ----------
FROM cgr.dev/chainguard/python:latest

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    VIRTUAL_ENV=/home/nonroot/venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

WORKDIR /app

# Copy the prebuilt venv and app
COPY --from=build $VIRTUAL_ENV $VIRTUAL_ENV
COPY . .

EXPOSE 5000

# Run your (code-instrumented) Flask app directly
ENTRYPOINT ["/home/nonroot/venv/bin/python", "/app/app.py"]
