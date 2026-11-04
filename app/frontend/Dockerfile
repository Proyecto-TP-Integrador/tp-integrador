FROM nginxinc/nginx-unprivileged:1.29-alpine

# Paquetes de Alpine con CVE HIGH corregidos después de publicada la imagen base
# (libxml2, pcre2, tiff, util-linux): se actualizan al construir y se vuelve al
# usuario sin privilegios de la imagen oficial (UID 101)
USER root
# hadolint ignore=DL3017
RUN apk upgrade --no-cache
USER 101
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html
HEALTHCHECK --interval=10s --timeout=3s --retries=5 CMD wget -q --spider http://127.0.0.1:8080/health || exit 1

