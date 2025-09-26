# -------- Build stage --------
FROM cgr.dev/chainguard/python:latest-dev AS build
ENV PATH="/app/venv/bin:$PATH"
WORKDIR /app

# venv + pip
RUN python -m venv /app/venv && python -m pip install --no-cache-dir --upgrade pip

# App deps first (if requirements.txt exists)
COPY requirements.txt ./
RUN if [ -f requirements.txt ]; then python -m pip install --no-cache-dir -r requirements.txt; fi

# === OpenTelemetry (minimal + compatible pins) ===
# Match SDK 1.37.0 with semconv/instrumentations 0.58b0
RUN python -m pip install --no-cache-dir \
    opentelemetry-sdk==1.37.0 \
    opentelemetry-exporter-otlp==1.37.0 \
    opentelemetry-instrumentation==0.58b0 \
    opentelemetry-instrumentation-flask==0.58b0 \
    opentelemetry-instrumentation-redis==0.58b0 \
    opentelemetry-semantic-conventions==0.58b0

# Copy the rest
COPY . .

# -------- Runtime stage --------
FROM cgr.dev/chainguard/python:latest
WORKDIR /app

# venv + app
COPY --from=build /app/venv /venv
COPY . ./
ENV PATH="/venv/bin:$PATH"

EXPOSE 5000

# Use auto-instrumentation wrapper; keep your code free of SDK/exporter wiring
ENTRYPOINT ["opentelemetry-instrument"]
CMD ["python", "/app/app.py"]
