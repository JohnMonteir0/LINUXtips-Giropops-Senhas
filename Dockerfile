# -------- Build stage --------
FROM cgr.dev/chainguard/python:latest-dev as build

ENV PATH="/app/venv/bin:$PATH"
WORKDIR /app

RUN python -m venv /app/venv
COPY . .

# Install deps
RUN pip install --no-cache-dir -r requirements.txt

# (optional but nice) install any extra auto-instr libs the distro suggests
# This runs inside the venv because PATH points to /app/venv/bin
RUN python -m opentelemetry.bootstrap -a install || true

# -------- Runtime stage --------
FROM cgr.dev/chainguard/python:latest
WORKDIR /app

# bring the venv across
COPY --from=build /app/venv /venv
COPY . ./
ENV PATH="/venv/bin:$PATH"

# OTel env (adjust endpoint/protocol for HTTP 4318)
ENV OTEL_SERVICE_NAME="flask-password-generator" \
    OTEL_EXPORTER_OTLP_ENDPOINT="http://otel-collector.giropops-senhas.svc.cluster.local:4318" \
    OTEL_EXPORTER_OTLP_PROTOCOL="http/protobuf" \
    OTEL_TRACES_EXPORTER="otlp" \
    OTEL_TRACES_SAMPLER="always_on" \
    OTEL_RESOURCE_ATTRIBUTES="deployment.environment=labs" \
    OTEL_LOG_LEVEL="info"

# Use the module form (works even if the console script isn't present)
ENTRYPOINT ["python", "-m", "opentelemetry.instrument", "python", "/app/app.py"]
