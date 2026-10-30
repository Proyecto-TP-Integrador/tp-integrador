# ── Stage 1: builder ────────────────────────────────────
FROM python:3.12-slim@sha256:a0f57064cbdcd6285fa45f51237ab0b35ea8ebaed06a1f5973e89e19dfb86704 AS builder

WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Stage 2: imagen final (sin herramientas de build) ───
FROM python:3.12-slim@sha256:a0f57064cbdcd6285fa45f51237ab0b35ea8ebaed06a1f5973e89e19dfb86704 AS final

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=5000

WORKDIR /app

# Copiar solo las dependencias instaladas desde el builder
COPY --from=builder /install /usr/local

# Usuario sin privilegios con UID/GID fijos y eliminación de bits setuid/setgid (Issue #1)
RUN groupadd --gid 10001 appuser \
 && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin appuser \
 && find / -xdev -perm /6000 -type f -exec chmod a-s {} +

# Código propiedad de root: el proceso de la app no puede modificarlo
COPY app.py entrypoint.sh ./
RUN chmod 0755 entrypoint.sh

USER 10001:10001

EXPOSE 5000
ENTRYPOINT ["./entrypoint.sh"]
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--worker-tmp-dir", "/dev/shm", "app:app"]
