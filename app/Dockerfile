FROM node:20-alpine

ARG APP_VERSION=dev
ENV NODE_ENV=production \
    APP_VERSION=${APP_VERSION} \
    PORT=8080

WORKDIR /app
COPY package.json ./
COPY server.js ./

# Run as the unprivileged "node" user shipped with the base image
USER node
EXPOSE 8080

# Container-level check (Nomad/Consul checks are the ones that matter for rollout)
HEALTHCHECK --interval=10s --timeout=2s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/health || exit 1

CMD ["node", "server.js"]
