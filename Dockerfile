# Build a small production image for the service.
FROM node:20-alpine

# curl is used by the container health check.
RUN apk add --no-cache curl

WORKDIR /usr/src/app

# Install dependencies first so Docker can cache this layer.
COPY app/package.json app/package-lock.json ./
RUN npm ci --omit=dev

# Copy the application source.
COPY app/ ./

# The service reads PORT from the environment and defaults to 3000.
EXPOSE 3000

CMD ["node", "server.js"]
