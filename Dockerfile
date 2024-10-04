# Use the official Python image based on Alpine
FROM python:3.11.9-alpine3.20

# Install necessary dependencies
RUN apk update && \
    apk add --no-cache git

# Set working directory inside the container
WORKDIR /app

# Clone the repository into the container
RUN git clone https://github.com/badtuxx/giropops-senhas.git /app/giropops-senhas

# Set the working directory to the cloned repo
WORKDIR /app/giropops-senhas

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Expose the Flask app port
EXPOSE 5000

# Command to run the Flask app
CMD ["flask", "run", "--host=0.0.0.0"]
