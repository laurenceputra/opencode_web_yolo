ARG BASE_IMAGE=node:20-slim
FROM ${BASE_IMAGE}

ARG OPENCODE_NPM_PACKAGE=opencode-ai
ARG OPENCODE_VERSION=latest
ARG WRAPPER_VERSION=0.0.0

ENV DEBIAN_FRONTEND=noninteractive
ENV OPENCODE_WEB_YOLO_HOME=/home/opencode

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gh \
    gosu \
    openssh-client \
    passwd \
    sudo \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g "${OPENCODE_NPM_PACKAGE}@${OPENCODE_VERSION}"

RUN mkdir -p /opt /workspace "${OPENCODE_WEB_YOLO_HOME}" /app \
  && opencode --version | tr -d '[:space:]' >/opt/opencode-version \
  && printf '%s\n' "${WRAPPER_VERSION}" >/opt/opencode-web-yolo-version

RUN cat <<'EOF' >/app/AGENTS.md
# opencode_web_yolo fallback instructions

This is a built-in fallback instruction file used when no host AGENTS.md is mounted.
EOF

COPY .opencode_web_yolo_entrypoint.sh /usr/local/bin/opencode_web_yolo_entrypoint.sh
RUN chmod +x /usr/local/bin/opencode_web_yolo_entrypoint.sh

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/opencode_web_yolo_entrypoint.sh"]
