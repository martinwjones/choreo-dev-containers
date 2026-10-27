FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

# Install k3d inside the container
RUN curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# Pre-create the Claude config dir so the named volume mounted there is owned by vscode, not root
RUN mkdir -p /home/vscode/.claude && chown vscode:vscode /home/vscode/.claude

# Set working directory
WORKDIR /workspace