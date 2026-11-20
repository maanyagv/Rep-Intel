# Backend image for Azure Container Apps (the FastAPI app in backend/).
# The website (frontend/) is NOT in this image: it is a static site published
# to Azure Static Web Apps by .github/workflows/azure-frontend.yml.
#
# Build from the repository root (CI builds linux/amd64):
#   docker build --platform linux/amd64 -f deploy/Dockerfile -t rep-tell .
# Behind a network that blocks pypi.org or Docker Hub, pass mirrors:
#   --build-arg PIP_INDEX_URL=https://<mirror>/simple
#   --build-arg PYTHON_IMAGE=public.ecr.aws/docker/library/python:3.12-slim
#
# Runs ONE uvicorn worker on purpose: backend/main.py starts a background
# collector loop at startup and keeps its status in memory, so more workers
# (or more replicas) would run the collectors several times over.

ARG PYTHON_IMAGE=python:3.12-slim

# ---------------------------------------------------------------------------
# 1. Install the Python packages into a virtual environment
# ---------------------------------------------------------------------------
FROM ${PYTHON_IMAGE} AS build
ARG PIP_INDEX_URL=https://pypi.org/simple
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_INDEX_URL=${PIP_INDEX_URL}
WORKDIR /src
# requirements.txt is UTF-16 with a byte-order mark; pip reads that as is.
COPY requirements.txt ./
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --upgrade pip \
 && /opt/venv/bin/pip install -r requirements.txt \
 && find /opt/venv -name '__pycache__' -type d -prune -exec rm -rf {} + \
 && rm -rf /opt/venv/lib/python*/site-packages/pip /opt/venv/bin/pip*

# ---------------------------------------------------------------------------
# 2. Small runtime image, non-root
# ---------------------------------------------------------------------------
FROM ${PYTHON_IMAGE} AS runtime
ENV PATH=/opt/venv/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8080
RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app
COPY --from=build /opt/venv /opt/venv
WORKDIR /app
COPY backend ./backend
# backend/data/*.json is the starting dataset; the app rewrites it while it
# runs (collector results, alerts), so the app user must own that folder.
# These changes live only in the running container: every new revision
# (deploy or settings change) starts again from the committed files.
RUN chown -R app:app /app/backend/data
USER 10001:10001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import os,urllib.request; urllib.request.urlopen('http://127.0.0.1:%s/api/health' % os.environ.get('PORT','8080'), timeout=4)" || exit 1
# Started from /app so "backend.*" imports resolve (backend/main.py imports
# backend.alerts.engine etc.). Listens on $PORT (Azure: 8080).
CMD ["sh", "-c", "exec uvicorn backend.main:app --host 0.0.0.0 --port \"${PORT:-8080}\" --workers 1 --proxy-headers --forwarded-allow-ips '*' --no-server-header"]
