# A genuine pinned v1 CLI on the same runtime dependencies/user/persistence setup.
# This acceptance image is never shipped as the production image.
FROM opencode_web_yolo:ci
RUN npm uninstall -g @opencode/cli \
    && npm install -g opencode-ai@1.19.5 \
    && test "$(opencode --version)" = 1.19.5
