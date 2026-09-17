# Build a production-ready image with a stable package manager for the health
# check and runtime dependencies.
FROM node:20-bookworm-slim

# curl is used by the container health check.
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app

# Install dependencies first so Docker can cache this layer.
COPY app/package.json ./
RUN npm install --omit=dev

# Copy the application source.
COPY app/ ./

# The service reads PORT from the environment and defaults to 8080 for local
# Compose and GitHub Actions smoke tests.
EXPOSE 8080

CMD ["node", "server.js"]
