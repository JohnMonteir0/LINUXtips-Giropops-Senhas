# -------- Build stage --------
FROM cgr.dev/chainguard/python:latest-dev AS build
ENV PATH="/app/venv/bin:$PATH"
WORKDIR /app

# Create and use venv
RUN python -m venv /app/venv

# Install deps
COPY requirements.txt .
RUN python -m pip install --no-cache-dir -r requirements.txt

# Copy app
COPY . .

# -------- Runtime stage --------
FROM cgr.dev/chainguard/python:latest
WORKDIR /app

# Bring venv + app
COPY --from=build /app/venv /venv
COPY . ./

ENV PATH="/venv/bin:$PATH"

# Run the app directly (we're using code-based OTEL init)
ENTRYPOINT ["python", "/app/app.py"]
