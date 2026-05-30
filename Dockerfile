# ------------------------------------------------------------------------------
# Super Optimized Multi-stage Dockerfile using Astral uv
# ------------------------------------------------------------------------------

# --- Build Stage ---
FROM python:3.12-slim AS builder

# Prevent python from writing pyc to disk during build phase (optional)
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Install build dependencies for compilation (if any native package requires it)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy the uv binary directly from the official image (extremely fast, no pip installation needed)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Set working directory
WORKDIR /build

# Create virtual environment
RUN uv venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy package config and lock files
COPY pyproject.toml uv.lock ./

# Install dependencies using cache mount to speed up subsequent docker builds dramatically
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --compile -r pyproject.toml

# --- Final Runtime Stage ---
FROM python:3.12-slim AS runner

# Optimize Python execution environment
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/opt/venv/bin:$PATH" \
    PORT=8000

# Install runtime utilities only (curl for healthchecks)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy the prepared virtual environment from the builder stage
COPY --from=builder /opt/venv /opt/venv

# Set up application folder
WORKDIR /app

# Copy the rest of the application code
COPY . .

# Create directory structure and set non-root user permission
RUN mkdir -p /app/data /app/logs && \
    useradd -m -u 1000 healthlink && \
    chown -R healthlink:healthlink /app

USER healthlink

# Expose backend port (can be overridden in docker-compose.yml for frontend)
EXPOSE 8000

# Default healthcheck for the backend API
HEALTHCHECK --interval=10s --timeout=5s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:8000/api/v1/health || exit 1

# Default launch command (FastAPI Backend)
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
