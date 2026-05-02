# Microsoft 의 Playwright base image — chromium + 필수 시스템 라이브러리 사전 설치.
# 이미지 크기 ~1GB 이지만 한 번만 pull (CronJob 매월 1회 + manual trigger 빈도).
FROM mcr.microsoft.com/playwright:v1.50.0-jammy

WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund

COPY server.js ./

ENV NODE_ENV=production \
    PORT=3001 \
    DEFAULT_TIMEOUT_MS=60000

EXPOSE 3001

# Health probe target
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD wget -qO- http://localhost:3001/healthz || exit 1

CMD ["node", "server.js"]
