# syntax=docker/dockerfile:1.7

FROM python:3.12-alpine@sha256:e064671ca452259bab50e8e2c7bd896e39e9a343bb06ca25234adf6fe18d0fc7 AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    UV_COMPILE_BYTECODE=0 \
    UV_LINK_MODE=copy

RUN pip install --no-cache-dir uv==0.13.7

WORKDIR /build
COPY pyproject.toml uv.lock ./
RUN uv export --frozen --no-dev --no-emit-project --output-file /tmp/requirements.txt \
    && uv pip install --system --prefix=/install -r /tmp/requirements.txt \
    && find /install -name '*.pyi' -delete

FROM alpine:3.23@sha256:469c9ea410b9215eaee7976ba6c0639039b444be8e5d638f7abbada189971eb2

ARG APP_VERSION=2.0.0
ARG VCS_REF=local
ARG BUILD_DATE=1970-01-01T00:00:00Z

LABEL org.opencontainers.image.title="devops-task-app" \
      org.opencontainers.image.description="FastAPI service with health checks and Prometheus metrics" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.licenses="MIT"

ENV APP_PORT=8080 \
    APP_ENV=production \
    LOG_LEVEL=INFO \
    APP_VERSION=${APP_VERSION} \
    PYTHONPATH=/usr/local/lib/python3.12/site-packages \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

RUN apk add --no-cache python3=3.12.16-r0 libstdc++=15.2.0-r2 libgcc=15.2.0-r2 \
    && addgroup -g 10001 -S app \
    && adduser -u 10001 -S -G app app \
    && rm -rf /usr/lib/python3.12/ensurepip \
              /usr/lib/python3.12/test \
              /usr/lib/python3.12/idlelib \
              /usr/lib/python3.12/tkinter \
              /usr/lib/python3.12/turtledemo \
              /usr/lib/python3.12/turtle.py \
              /usr/lib/python3.12/lib2to3 \
              /usr/lib/python3.12/pydoc_data \
              /usr/lib/python3.12/venv \
              /usr/lib/python3.12/config-3.12-* \
              /usr/lib/python3.12/site-packages/pip* \
              /usr/lib/python3.12/site-packages/setuptools* \
              /usr/lib/python3.12/site-packages/wheel* \
              /usr/bin/pip* \
              /usr/bin/idle* \
              /usr/bin/pydoc* \
              /usr/bin/2to3* \
    && rm -f /sbin/apk /lib/libapk.so* /usr/lib/libapk.so* \
    && rm -f /bin/sh /bin/ash

WORKDIR /app
COPY --from=builder /install /usr/local
COPY --chown=10001:10001 app /app/app

USER 10001:10001
EXPOSE 8080
STOPSIGNAL SIGTERM

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["python3", "-c", "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:' + os.environ.get('APP_PORT', '8080') + '/health', timeout=2)"]

ENTRYPOINT ["python3", "-m", "app"]
