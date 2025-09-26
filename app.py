from flask import Flask, render_template, request, jsonify
import redis
import string
import random
import os
import logging

# --- Only the OTEL API (no SDK wiring here) ---
from opentelemetry import trace
from opentelemetry.trace import Status, StatusCode

# Plain Prometheus client for /metrics scraping
from prometheus_client import Counter, generate_latest

# Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("giropops-senhas")

# Tracer is provided by the auto-instrumentation runtime
tracer = trace.get_tracer(__name__)

# Prometheus counter (not OTEL metrics)
senha_counter = Counter("senha_gerada_total", "Total de senhas geradas")

# --- Flask app (auto-instrumentation will hook Flask/Redis automatically) ---
app = Flask(__name__)

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

# -------- Custom spans (these are fine) --------
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

# Prometheus metrics endpoint (plain client)
@app.route("/metrics")
def metrics_endpoint():
    return generate_latest()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)