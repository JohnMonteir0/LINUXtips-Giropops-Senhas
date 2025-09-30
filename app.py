from flask import Flask, render_template, request, jsonify
import redis
import string
import random
import os
import logging
import atexit

# --- OpenTelemetry SDK (in-process) ---
from opentelemetry import trace
from opentelemetry.trace import Status, StatusCode
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.redis import RedisInstrumentor
from opentelemetry.instrumentation.logging import LoggingInstrumentor

# Prometheus metrics (plain client)
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST

# ---------- Config ----------
SERVICE_NAME = os.environ.get("OTEL_SERVICE_NAME", "giropops-senhas")
ENV = os.environ.get("DEPLOY_ENV", os.environ.get("ENV", "dev"))

# Prefer a single base endpoint for all signals (Collector service)
# For gRPC exporter: the endpoint is "host:port" (no scheme). Keep "insecure=True" for plaintext.
OTLP_ENDPOINT = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "otel-collector:4317")

# Optional extra resource attrs via env (e.g., "service.namespace=backend,cloud.platform=eks")
EXTRA_RESOURCE_ATTRS = os.environ.get("OTEL_RESOURCE_ATTRIBUTES", "")

# ---------- Logging (with trace context injection) ----------
# Keep root logger simple; OTel LoggingInstrumentor will inject trace IDs.
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
logger = logging.getLogger("giropops-senhas")

# ---------- OTEL Tracing setup ----------
# Build Resource from service.name + environment + any extra attributes
base_attrs = {
    "service.name": SERVICE_NAME,
    "deployment.environment": ENV,
}
if EXTRA_RESOURCE_ATTRS:
    # Merge "k=v" comma-list into base attrs (ignore malformed pairs)
    for kv in EXTRA_RESOURCE_ATTRS.split(","):
        if "=" in kv:
            k, v = kv.split("=", 1)
            base_attrs[k.strip()] = v.strip()

resource = Resource.create(base_attrs)

provider = TracerProvider(resource=resource)
exporter = OTLPSpanExporter(
    endpoint=OTLP_ENDPOINT,  # "host:port" for gRPC
    insecure=True,           # plaintext to Collector/Jaeger all-in-one
)
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)

# Ensure spans are flushed at process exit (useful for short-lived runs)
def _shutdown_tracing():
    try:
        trace.get_tracer_provider().shutdown()
    except Exception:
        pass

atexit.register(_shutdown_tracing)

# ---------- Flask app + auto-instrument libs ----------
app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)
RedisInstrumentor().instrument()              # traces redis calls
LoggingInstrumentor().instrument(             # inject trace_id/span_id into logs
    set_logging_format=True,                  # adds %(otelTraceID)s %(otelSpanID)s
    log_level=logging.INFO
)

# ---------- Redis client ----------
redis_host = os.environ.get("REDIS_HOST", "redis-service")
redis_port = int(os.environ.get("REDIS_PORT", "6379"))
redis_password = os.environ.get("REDIS_PASSWORD", "")

r = redis.StrictRedis(
    host=redis_host,
    port=redis_port,
    password=redis_password,
    decode_responses=True,
)

# ---------- Prometheus metric ----------
senha_counter = Counter("senha_gerada_total", "Total de senhas geradas")

# ---------- App code ----------
def criar_senha(tamanho, incluir_numeros, incluir_caracteres_especiais):
    with tracer.start_as_current_span("criar_senha") as span:
        span.set_attribute("senha.tamanho", tamanho)
        span.set_attribute("senha.incluir_numeros", bool(incluir_numeros))
        span.set_attribute("senha.incluir_caracteres_especiais", bool(incluir_caracteres_especiais))

        caracteres = string.ascii_letters
        if incluir_numeros:
            caracteres += string.digits
        if incluir_caracteres_especiais:
            caracteres += string.punctuation

        senha = "".join(random.choices(caracteres, k=tamanho))
        span.set_attribute("senha.preview_len", min(len(senha), 3))  # example attr, not the value itself
        return senha

@app.route("/", methods=["GET", "POST"])
def index():
    with tracer.start_as_current_span("index_handler") as span:
        try:
            if request.method == "POST":
                tamanho = int(request.form.get("tamanho", 8))
                incluir_numeros = request.form.get("incluir_numeros") == "on"
                incluir_caracteres_especiais = request.form.get("incluir_caracteres_especiais") == "on"

                span.set_attribute("form.tamanho", tamanho)
                span.set_attribute("form.incluir_numeros", incluir_numeros)
                span.set_attribute("form.incluir_caracteres_especiais", incluir_caracteres_especiais)

                senha = criar_senha(tamanho, incluir_numeros, incluir_caracteres_especiais)

                with tracer.start_as_current_span("redis.lpush") as rspan:
                    rspan.set_attribute("redis.list", "senhas")
                    r.lpush("senhas", senha)

                senha_counter.inc()

            with tracer.start_as_current_span("redis.lrange") as rspan:
                rspan.set_attribute("redis.list", "senhas")
                senhas = r.lrange("senhas", 0, 9)

            if senhas:
                senhas_geradas = [{"id": idx + 1, "senha": s} for idx, s in enumerate(senhas)]
                return render_template("index.html", senhas_geradas=senhas_geradas, senha=senhas_geradas[0]["senha"])
            return render_template("index.html")

        except Exception as exc:
            span.record_exception(exc)
            span.set_status(Status(StatusCode.ERROR, str(exc)))
            logger.exception("Error handling index request")
            return "Internal Server Error", 500

@app.route("/api/gerar-senha", methods=["POST"])
def gerar_senha_api():
    with tracer.start_as_current_span("gerar_senha_api") as span:
        try:
            dados = request.get_json() or {}
            tamanho = int(dados.get("tamanho", 8))
            incluir_numeros = bool(dados.get("incluir_numeros", False))
            incluir_caracteres_especiais = bool(dados.get("incluir_caracteres_especiais", False))

            span.set_attribute("json.tamanho", tamanho)
            span.set_attribute("json.incluir_numeros", incluir_numeros)
            span.set_attribute("json.incluir_caracteres_especiais", incluir_caracteres_especiais)

            senha = criar_senha(tamanho, incluir_numeros, incluir_caracteres_especiais)

            with tracer.start_as_current_span("redis.lpush") as rspan:
                rspan.set_attribute("redis.list", "senhas")
                r.lpush("senhas", senha)

            senha_counter.inc()
            return jsonify({"senha": senha})
        except Exception as exc:
            span.record_exception(exc)
            span.set_status(Status(StatusCode.ERROR, str(exc)))
            logger.exception("Error in /api/gerar-senha")
            return jsonify({"error": "internal"}), 500

@app.route("/api/senhas", methods=["GET"])
def listar_senhas():
    with tracer.start_as_current_span("listar_senhas") as span:
        try:
            with tracer.start_as_current_span("redis.lrange") as rspan:
                rspan.set_attribute("redis.list", "senhas")
                senhas = r.lrange("senhas", 0, 9)

            resposta = [{"id": idx + 1, "senha": s} for idx, s in enumerate(senhas)]
            span.set_attribute("senhas.count", len(resposta))
            return jsonify(resposta)
        except Exception as exc:
            span.record_exception(exc)
            span.set_status(Status(StatusCode.ERROR, str(exc)))
            logger.exception("Error in /api/senhas")
            return jsonify({"error": "internal"}), 500

# Health + Prometheus metrics
@app.route("/healthz")
def healthz():
    return jsonify({"status": "ok"}), 200

@app.route("/metrics")
def metrics_endpoint():
    data = generate_latest()
    return data, 200, {"Content-Type": CONTENT_TYPE_LATEST}

if __name__ == "__main__":
    # In production, prefer Gunicorn: `gunicorn -w 2 -b 0.0.0.0:5000 wsgi:app`
    app.run(host="0.0.0.0", port=5000, debug=True)
