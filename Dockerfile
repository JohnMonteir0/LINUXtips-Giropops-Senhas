# -------- Build stage --------
FROM cgr.dev/chainguard/python:latest-dev as build
ENV PATH="/app/venv/bin:$PATH"
WORKDIR /app

# Create venv
RUN python -m venv /app/venv

# Copy sources and requirements
COPY requirements.txt .
RUN python -m pip install --no-cache-dir -r requirements.txt

COPY . .

# -------- Runtime stage --------
FROM cgr.dev/chainguard/python:latest
WORKDIR /app

# Copy venv + app code
COPY --from=build /app/venv /venv
COPY . ./

ENV PATH="/venv/bin:$PATH"


ENTRYPOINT ["python", "/app/app.py"]