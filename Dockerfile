FROM node:22.12.0-alpine

WORKDIR /app

# Install build dependencies. bash is required explicitly: the agent-server's
# interactive terminal/PTY tooling looks for a real bash binary and fails with
# "Could not find bash in PATH" on Alpine's default busybox ash shell.
RUN apk add --no-cache bash python3 make g++ curl

# Install uv (for Python agent-server)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"

# Copy package files
COPY package.json package-lock.json ./

# Install npm dependencies
RUN npm ci

# Copy source code
COPY . .

# Expose ports
# 3001: Frontend (Vite dev server)
# 8000: Ingress proxy
# 18000: Agent Server
EXPOSE 3001 8000 18000

# Default command: run dev stack
CMD ["npm", "run", "dev"]
