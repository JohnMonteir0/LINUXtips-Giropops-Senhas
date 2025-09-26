# ---------- Build ----------
FROM cgr.dev/chainguard/python:latest-dev AS build

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    VIRTUAL_ENV=/home/nonroot/venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

WORKDIR /app

RUN python -m venv "$VIRTUAL_ENV" \
 && python -m pip install --no-cache-dir --upgrade pip setuptools wheel

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# ---------- Runtime ----------
FROM cgr.dev/chainguard/python:latest

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    VIRTUAL_ENV=/home/nonroot/venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

WORKDIR /app

COPY --from=build $VIRTUAL_ENV $VIRTUAL_ENV
COPY . .

EXPOSE 5000

# Use the venv python explicitly
ENTRYPOINT ["/home/nonroot/venv/bin/python", "/app/app.py"]
# (For Gunicorn in prod, use:)
# ENTRYPOINT ["/home/nonroot/venv/bin/gunicorn","-w","2","-b","0.0.0.0:5000","app:app"]
