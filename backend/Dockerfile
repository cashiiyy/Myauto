# ─────────────────────────────────────────────────────────────────────────────
# MyAuto Backend — Multi-Stage Production Dockerfile (Python 3.12 FastAPI)
# ─────────────────────────────────────────────────────────────────────────────

# ── Stage 1: Build & Wheels ───────────────────────────────────────────────────
FROM python:3.12-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build

# Install build-time OS dependencies for compiling C-extensions (asyncpg, psycopg2)
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy and install python dependencies
COPY requirements.txt .
RUN pip wheel --no-cache-dir --no-deps --wheel-dir /build/wheels -r requirements.txt


# ── Stage 2: Runtime Image ────────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app

WORKDIR /app

# Install runtime OS dependencies only (libpq for postgres client, curl for healthcheck)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install python wheels from builder stage
COPY --from=builder /build/wheels /wheels
COPY --from=builder /build/requirements.txt .
RUN pip install --no-cache-dir /wheels/* && rm -rf /wheels

# Create non-root user for security
RUN useradd --system --no-create-home --shell /bin/false myauto \
    && mkdir -p /app/secrets \
    && chown -R myauto:myauto /app

# Copy application source, migrations, and alembic config
COPY --chown=myauto:myauto alembic.ini .
COPY --chown=myauto:myauto migrations/ ./migrations/
COPY --chown=myauto:myauto app/ ./app/

# Switch to non-root user
USER myauto

# Expose port
EXPOSE 8919

# Health check probe against GET /health
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -f http://localhost:8919/health || exit 1

# Start Uvicorn single worker (optimised for resource-constrained Intel i3/8GB home server)
CMD ["python", "-m", "uvicorn", "app.main:app", \
     "--host", "0.0.0.0", \
     "--port", "8919", \
     "--workers", "1", \
     "--log-level", "info"]
