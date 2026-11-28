FROM node:22-bookworm-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends bubblewrap ca-certificates ffmpeg poppler-utils tesseract-ocr tesseract-ocr-spa tesseract-ocr-eng unzip && rm -rf /var/lib/apt/lists/*
COPY package*.json ./
RUN npm ci --omit=dev
ARG CODEX_VERSION=0.160.0
RUN npm install --global @openai/codex@${CODEX_VERSION}
COPY server.mjs codex_runtime.mjs ./
ENV NODE_ENV=production
EXPOSE 8787
CMD ["node", "server.mjs"]
