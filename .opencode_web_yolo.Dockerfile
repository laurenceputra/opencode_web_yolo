ARG BASE_IMAGE=node:20-slim
FROM ${BASE_IMAGE}

ARG NPM_VERSION=11.10.1
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

RUN npm install -g "npm@${NPM_VERSION}"

RUN if [ "${OPENCODE_VERSION}" = "latest" ]; then \
      npm install -g "${OPENCODE_NPM_PACKAGE}" ; \
    else \
      npm install -g "${OPENCODE_NPM_PACKAGE}@${OPENCODE_VERSION}" ; \
    fi

RUN mkdir -p /opt /workspace "${OPENCODE_WEB_YOLO_HOME}" /app \
  && opencode --version | tr -d '[:space:]' >/opt/opencode-version \
  && printf '%s\n' "${WRAPPER_VERSION}" >/opt/opencode-web-yolo-version

COPY AGENTS.md /app/AGENTS.md

COPY .opencode_web_yolo_entrypoint.sh /usr/local/bin/opencode_web_yolo_entrypoint.sh
RUN chmod +x /usr/local/bin/opencode_web_yolo_entrypoint.sh

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/opencode_web_yolo_entrypoint.sh"]
