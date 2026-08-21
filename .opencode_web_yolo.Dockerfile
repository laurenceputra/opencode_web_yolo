ARG BASE_IMAGE=node:22-slim
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive
ENV OPENCODE_WEB_YOLO_HOME=/home/opencode
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

RUN mkdir -p "${PLAYWRIGHT_BROWSERS_PATH}" \
  && chmod 1777 "${PLAYWRIGHT_BROWSERS_PATH}"

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

ARG OPENCODE_NPM_PACKAGE=opencode-ai
ARG OPENCODE_VERSION=latest
RUN npm install -g "${OPENCODE_NPM_PACKAGE}@${OPENCODE_VERSION}"

ARG OPENCODE_WEB_BUILD_PLAYWRIGHT=0
ARG PLAYWRIGHT_VERSION=1.62.1
RUN if [ "${OPENCODE_WEB_BUILD_PLAYWRIGHT}" = "1" ]; then \
      npm install -g "@playwright/test@${PLAYWRIGHT_VERSION}" \
      && playwright_package_dir="$(npm root -g)/@playwright/test" \
      && installed_playwright_version="$(node -e 'process.stdout.write(require(process.argv[1]).version)' "$playwright_package_dir/package.json")" \
      && [ "${installed_playwright_version}" = "${PLAYWRIGHT_VERSION}" ] \
      && playwright install --with-deps chromium \
      && chmod -R a+rX "${PLAYWRIGHT_BROWSERS_PATH}"; \
    fi

ARG OPENCODE_WEB_BUILD_WRANGLER=0
RUN if [ "${OPENCODE_WEB_BUILD_WRANGLER}" = "1" ]; then \
      npm install -g wrangler@latest; \
    fi

ARG WRAPPER_VERSION=0.0.0
RUN mkdir -p /opt /workspace "${OPENCODE_WEB_YOLO_HOME}" /app \
  && opencode --version | tr -d '[:space:]' >/opt/opencode-version \
  && printf '%s\n' "${WRAPPER_VERSION}" >/opt/opencode-web-yolo-version \
  && printf '%s\n' "${OPENCODE_WEB_BUILD_PLAYWRIGHT}" >/opt/opencode-web-yolo-playwright \
  && printf '%s\n' "${PLAYWRIGHT_VERSION}" >/opt/opencode-web-yolo-playwright-expected-version \
  && if [ "${OPENCODE_WEB_BUILD_PLAYWRIGHT}" = "1" ]; then \
       playwright_package_dir="$(npm root -g)/@playwright/test" \
       && node -e 'process.stdout.write(require(process.argv[1]).version)' "$playwright_package_dir/package.json" >/opt/opencode-web-yolo-playwright-version; \
     else \
       printf '%s\n' disabled >/opt/opencode-web-yolo-playwright-version; \
     fi \
  && printf '%s\n' "${OPENCODE_WEB_BUILD_WRANGLER}" >/opt/opencode-web-yolo-wrangler

RUN cat <<'EOF' >/app/AGENTS.md
# opencode_web_yolo fallback instructions

This is a built-in fallback instruction file used when no host AGENTS.md is mounted.
EOF

COPY .opencode_web_yolo_entrypoint.sh /usr/local/bin/opencode_web_yolo_entrypoint.sh
RUN chmod +x /usr/local/bin/opencode_web_yolo_entrypoint.sh

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/opencode_web_yolo_entrypoint.sh"]
