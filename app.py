from flask import Flask, render_template, request, jsonify
import redis
import string
import random
import os
import logging

# --- OpenTelemetry SDK (in-process) ---
from opentelemetry import trace
from opentelemetry.trace import Status, StatusCode
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.redis import RedisInstrumentor

# Prometheus metrics (plain client)
from prometheus_client import Counter, generate_latest

# ---------- Config ----------
SERVICE_NAME = os.environ.get("OTEL_SERVICE_NAME", "giropops-senhas")
# Prefer env if provided; default to docker-compose service "jaeger:4317"
OTLP_TRACES_ENDPOINT = os.environ.get(
    "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT",
    "jaeger:4317",
)

# ---------- Logging ----------
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("giropops-senhas")

# ---------- OTEL Tracing setup ----------
resource = Resource.create({"service.name": SERVICE_NAME})

provider = TracerProvider(resource=resource)
exporter = OTLPSpanExporter(
    endpoint=OTLP_TRACES_ENDPOINT,  # host:port (no scheme)
    insecure=True,                  # Jaeger all-in-one default is plaintext
)
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)

# ---------- Flask app + auto-instrument libs ----------
app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)
RedisInstrumentor().instrument()

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

        return "".join(random.choices(caracteres, k=tamanho))

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

                with tracer.start_as_current_span("redis_lpush") as rspan:
                    rspan.set_attribute("redis.list", "senhas")
                    r.lpush("senhas", senha)

                senha_counter.inc()

            with tracer.start_as_current_span("redis_lrange") as rspan:
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
            incluir_numeros = dados.get("incluir_numeros", False)
            incluir_caracteres_especiais = dados.get("incluir_caracteres_especiais", False)

            span.set_attribute("json.tamanho", tamanho)
            span.set_attribute("json.incluir_numeros", incluir_numeros)
            span.set_attribute("json.incluir_caracteres_especiais", incluir_caracteres_especiais)

            senha = criar_senha(tamanho, incluir_numeros, incluir_caracteres_especiais)

            with tracer.start_as_current_span("redis_lpush") as rspan:
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
            with tracer.start_as_current_span("redis_lrange") as rspan:
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

# Prometheus metrics endpoint
@app.route("/metrics")
def metrics_endpoint():
    return generate_latest()

if __name__ == "__main__":
    # DEBUG=True is fine locally; disable in prod.
    app.run(host="0.0.0.0", port=5000, debug=True)
