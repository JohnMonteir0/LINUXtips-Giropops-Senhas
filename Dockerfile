# Use the official Python chainguard image
FROM cgr.dev/chainguard/python:latest-dev as build

ENV PATH="/app/venv/bin:$PATH"

# Set working directory inside the container
WORKDIR /app

# Set virtual environment
RUN python -m venv /app/venv
COPY . .

RUN pip install --no-cache-dir -r requirements.txt

# Build production image from build stage
FROM cgr.dev/chainguard/python:latest

WORKDIR /app

ENV PATH="/venv/bin:$PATH"

COPY . ./
COPY --from=build /app/venv /venv

# Command to run the Flask app
ENTRYPOINT [ "python", "/app/app.py" ]
