# ==============================================================================
# Dockerfile for Phoenix LiveView Application
# Following August 2025 best practices: multi-stage builds, security, optimization
# ==============================================================================

# Argument for Elixir/OTP versions - allows easy updates
ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=27
ARG ALPINE_VERSION=3.20

# ==============================================================================
# STAGE 1: Build Environment
# ==============================================================================
FROM elixir:${ELIXIR_VERSION}-otp-${OTP_VERSION}-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    nodejs \
    npm \
    && rm -rf /var/cache/apk/*

# Set build environment
ENV MIX_ENV=prod
ENV DEBIAN_FRONTEND=noninteractive
ENV ERL_AFLAGS="-kernel shell_history enabled"

# Create app directory
WORKDIR /app

# Install hex and rebar (build tools)
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy dependency files first (for better caching)
COPY mix.exs mix.lock ./

# Install and compile dependencies in one step to avoid module conflicts
RUN mix deps.get --only=prod && \
    mix deps.compile

# Copy configuration files
COPY config ./config

# Copy assets for building
COPY assets ./assets
COPY priv ./priv

# Setup and build assets (following the project's setup alias)
RUN mix assets.setup && \
    mix assets.deploy

# Copy source code
COPY lib ./lib

# Compile application
RUN mix compile

# Build release
RUN mix release

# ==============================================================================
# STAGE 2: Runtime Environment
# ==============================================================================
FROM alpine:${ALPINE_VERSION} AS runtime

# Install runtime dependencies
RUN apk add --no-cache \
    openssl \
    ncurses-libs \
    && rm -rf /var/cache/apk/*

# Create non-root user for security
RUN addgroup -g 1000 elixir && \
    adduser -u 1000 -G elixir -s /bin/sh -D elixir

# Set runtime environment
ENV MIX_ENV=prod
ENV PHX_SERVER=true
ENV PORT=3000

# Create necessary directories with proper permissions
RUN mkdir -p /app/priv/data/chat_logs \
             /app/priv/data/uploads \
             /app/priv/data && \
    chown -R elixir:elixir /app

# Switch to non-root user
USER elixir
WORKDIR /app

# Copy release from builder stage
COPY --from=builder --chown=elixir:elixir /app/_build/prod/rel/live_ai_chat ./

# Copy static assets from builder
COPY --from=builder --chown=elixir:elixir /app/priv/static ./priv/static

# Create volumes for persistent data
VOLUME ["/app/priv/data"]

# Expose port
EXPOSE ${PORT}

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:${PORT}/ || exit 1

# Runtime configuration
ENV SHELL=/bin/sh

# Start the application
CMD ["./bin/live_ai_chat", "start"]
