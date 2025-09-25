# -------- Build stage --------
FROM cgr.dev/chainguard/python:latest-dev as build

ENV PATH="/app/venv/bin:$PATH"

# Set working directory inside the container
WORKDIR /app

# Create virtual environment
RUN python -m venv /app/venv

# Copy source
COPY . .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt
RUN opentelemetry-bootstrap -a install

# -------- Runtime stage --------
FROM cgr.dev/chainguard/python:latest

WORKDIR /app

# Copy venv from build stage
COPY --from=build /app/venv /venv
COPY . ./

ENV PATH="/venv/bin:$PATH"

# --- OpenTelemetry configuration ---
# Service name (shows up in traces)
ENV OTEL_SERVICE_NAME="flask-password-generator"

# Endpoint for OTLP (default OTEL Collector in Kubernetes)
# Change if running locally: e.g., http://localhost:4318
ENV OTEL_EXPORTER_OTLP_ENDPOINT="http://otel-collector:4318"

# Enable both traces and metrics
ENV OTEL_TRACES_EXPORTER="otlp"
ENV OTEL_METRICS_EXPORTER="otlp"
# (Prometheus reader is still exposed on /metrics by your app)

# Optional: log level
ENV OTEL_LOG_LEVEL="info"

# Entrypoint: run Flask app
ENTRYPOINT [ "opentelemetry-instrument", "python", "/app/app.py" ]

