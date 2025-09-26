from flask import Flask, render_template, request, jsonify
import redis
import string
import random
import os
import logging

# --- OpenTelemetry setup ---
from opentelemetry import trace, metrics
from opentelemetry.sdk.resources import SERVICE_NAME, Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
# Use gRPC exporters (not HTTP)
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.prometheus import PrometheusMetricReader
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.redis import RedisInstrumentor
from opentelemetry.trace import Status, StatusCode

# Resource (service name, etc.)
resource = Resource(attributes={SERVICE_NAME: "giropops-senhas"})

# ---- Traces (gRPC -> Collector :4317, plaintext) ----
trace.set_tracer_provider(TracerProvider(resource=resource))
tracer_provider = trace.get_tracer_provider()
otlp_traces = OTLPSpanExporter(
    endpoint="otel-collector.giropops-senhas.svc.cluster.local:4317",  # gRPC: host:port (no scheme)
    insecure=True,                                                     # Collector is plaintext
)
tracer_provider.add_span_processor(BatchSpanProcessor(otlp_traces))
tracer = trace.get_tracer(__name__)

# ---- Metrics: Prometheus + OTLP gRPC (plaintext) ----
prom_reader = PrometheusMetricReader()  # exposes /metrics via prometheus_client
otlp_metrics = OTLPMetricExporter(
    endpoint="otel-collector.giropops-senhas.svc.cluster.local:4317",  # gRPC
    insecure=True,
)
metrics.set_meter_provider(
    MeterProvider(
        resource=resource,
        metric_readers=[
            prom_reader,
            PeriodicExportingMetricReader(otlp_metrics),
        ],
    )
)
meter = metrics.get_meter(__name__)
senha_counter = meter.create_counter(
    "senha_gerada_total", description="Total de senhas geradas"
)

# Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("giropops-senhas")

# --- Flask app + auto-instrumentation ---
app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)  # traces HTTP routes
RedisInstrumentor().instrument()         # traces redis commands

# Redis client
redis_host = os.environ.get("REDIS_HOST", "redis-service")
redis_port = 6379
redis_password = ""
r = redis.StrictRedis(
    host=redis_host,
    port=redis_port,
    password=redis_password,
    decode_responses=True,
)

# -------- Custom spans --------
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

        senha = ''.join(random.choices(caracteres, k=tamanho))
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

                with tracer.start_as_current_span("redis_lpush") as rspan:
                    rspan.set_attribute("redis.list", "senhas")
                    r.lpush("senhas", senha)

                senha_counter.add(1)

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

            senha_counter.add(1)
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
    from prometheus_client import generate_latest
    return generate_latest()

if __name__ == "__main__":
    # You can switch debug to False for prod
    app.run(host="0.0.0.0", port=5000, debug=True)