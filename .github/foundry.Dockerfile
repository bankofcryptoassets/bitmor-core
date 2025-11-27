FROM ghcr.io/foundry-rs/foundry

# Install dependencies that might be needed
RUN apt-get update && apt-get install -y \
    git \
    curl \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Install slither
RUN pip3 install slither-analyzer

# Set working directory
WORKDIR /workspace

# This will be the base image with foundry pre-installed
