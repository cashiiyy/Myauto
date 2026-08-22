# ─────────────────────────────────────────────────────────────────────────────
# MyAuto Backend — Dockerfile
# Multi-stage build: builder installs deps, runtime is lean
# ─────────────────────────────────────────────────────────────────────────────

# ── Stage 1: dependency builder ───────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build

# Install build deps needed for some Python packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --upgrade pip \
    && pip install --prefix=/install --no-cache-dir -r requirements.txt

# ── Stage 2: runtime ──────────────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

WORKDIR /app

# Runtime system deps only
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Copy application source
COPY app/ ./app/
COPY migrations/ ./migrations/
COPY alembic.ini .

# Create secrets directory (actual file is bind-mounted at runtime, never baked in)
RUN mkdir -p /app/secrets

# Non-root user for security
RUN useradd --system --no-create-home --shell /bin/false myauto
RUN chown -R myauto:myauto /app
USER myauto

# Expose application port
EXPOSE 8000

# Health check — uses the /health endpoint
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Default: run uvicorn with graceful shutdown
CMD ["uvicorn", "app.main:app", \
     "--host", "0.0.0.0", \
     "--port", "8000", \
     "--workers", "1", \
     "--loop", "uvloop", \
     "--log-level", "info", \
     "--access-log"]
