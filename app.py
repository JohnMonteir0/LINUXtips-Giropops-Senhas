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
from opentelemetry.sdk.metrics.export import (
    PeriodicExportingMetricReader,
)
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.prometheus import PrometheusMetricReader
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.redis import RedisInstrumentor

# Configure resource (service name, etc.)
resource = Resource(attributes={
    SERVICE_NAME: "flask-password-generator"
})

# Traces
trace.set_tracer_provider(TracerProvider(resource=resource))
tracer_provider = trace.get_tracer_provider()
otlp_exporter = OTLPSpanExporter(endpoint="http://otel-collector:4318/v1/traces")
tracer_provider.add_span_processor(BatchSpanProcessor(otlp_exporter))

# Metrics
prom_reader = PrometheusMetricReader()  # exposes /metrics endpoint
metric_exporter = OTLPMetricExporter(endpoint="http://otel-collector:4318/v1/metrics")

metrics.set_meter_provider(
    MeterProvider(
        resource=resource,
        metric_readers=[
            prom_reader,
            PeriodicExportingMetricReader(metric_exporter)
        ]
    )
)
meter = metrics.get_meter(__name__)
senha_counter = meter.create_counter(
    "senha_gerada_total",
    description="Total de senhas geradas"
)

# Logging (OTel logger integration possible too)
logging.basicConfig(level=logging.INFO)

# --- Flask app ---
app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)  # auto-instrument routes
RedisInstrumentor().instrument()         # auto-instrument redis

redis_host = os.environ.get("REDIS_HOST", "redis-service")
redis_port = 6379
redis_password = ""
r = redis.StrictRedis(
    host=redis_host,
    port=redis_port,
    password=redis_password,
    decode_responses=True
)

def criar_senha(tamanho, incluir_numeros, incluir_caracteres_especiais):
    caracteres = string.ascii_letters
    if incluir_numeros:
        caracteres += string.digits
    if incluir_caracteres_especiais:
        caracteres += string.punctuation
    return ''.join(random.choices(caracteres, k=tamanho))

@app.route("/", methods=["GET", "POST"])
def index():
    if request.method == "POST":
        tamanho = int(request.form.get("tamanho", 8))
        incluir_numeros = request.form.get("incluir_numeros") == "on"
        incluir_caracteres_especiais = request.form.get("incluir_caracteres_especiais") == "on"

        senha = criar_senha(tamanho, incluir_numeros, incluir_caracteres_especiais)
        r.lpush("senhas", senha)
        senha_counter.add(1)

    senhas = r.lrange("senhas", 0, 9)
    if senhas:
        senhas_geradas = [{"id": idx + 1, "senha": senha} for idx, senha in enumerate(senhas)]
        return render_template("index.html", senhas_geradas=senhas_geradas, senha=senhas_geradas[0]["senha"])
    return render_template("index.html")

@app.route("/api/gerar-senha", methods=["POST"])
def gerar_senha_api():
    dados = request.get_json()
    tamanho = int(dados.get("tamanho", 8))
    incluir_numeros = dados.get("incluir_numeros", False)
    incluir_caracteres_especiais = dados.get("incluir_caracteres_especiais", False)

    senha = criar_senha(tamanho, incluir_numeros, incluir_caracteres_especiais)
    r.lpush("senhas", senha)
    senha_counter.add(1)

    return jsonify({"senha": senha})

@app.route("/api/senhas", methods=["GET"])
def listar_senhas():
    senhas = r.lrange("senhas", 0, 9)
    return jsonify([{"id": idx + 1, "senha": senha} for idx, senha in enumerate(senhas)])

# Prometheus metrics endpoint (from PrometheusMetricReader)
@app.route("/metrics")
def metrics_endpoint():
    from prometheus_client import generate_latest
    return generate_latest()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)