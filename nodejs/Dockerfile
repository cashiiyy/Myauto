FROM node:20-alpine AS base
WORKDIR /app

# ── Dependencies ──────────────────────────────────────────────────────────────
FROM base AS deps
COPY package.json package-lock.json* ./
RUN npm ci --only=production && npm cache clean --force

# ── Runtime ───────────────────────────────────────────────────────────────────
FROM base AS runtime
# Non-root user for security
RUN addgroup -S myauto && adduser -S myauto -G myauto
USER myauto

COPY --from=deps --chown=myauto:myauto /app/node_modules ./node_modules
COPY --chown=myauto:myauto src/ ./src/

EXPOSE 3001

HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -qO- http://localhost:3001/health || exit 1

CMD ["node", "src/index.js"]
