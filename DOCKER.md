# Docker Deployment Guide

This guide covers containerized deployment of the Phoenix LiveView AI Chat application using August 2025 Docker best practices.

## Quick Start

### Prerequisites
- Docker 24.0+ with BuildKit enabled
- Docker Compose v2.20+
- Environment variables configured (see below)

### Build and Run

```bash
# Build the image
./build.sh

# Run with Docker Compose (recommended)
docker-compose up -d

# Or run directly
./build.sh run
```

## Environment Variables

### Required
- `SECRET_KEY_BASE` - Generate with `mix phx.gen.secret`
- `VERTEXAI_PROJECT` - Your Google Cloud project ID

### Optional
- `PHX_HOST` - Hostname (default: localhost)
- `PORT` - Port number (default: 3000)
- `VERTEXAI_LOCATION` - GCP region (default: europe-west1)
- `GEMINI_MODEL` - AI model (default: gemini-2.5-flash)
- `GOOGLE_APPLICATION_CREDENTIALS` - Path to service account JSON
- `GOOGLE_SERVICE_ACCOUNT_JSON` - Inline service account JSON

### Example .env file
```bash
SECRET_KEY_BASE=your_secret_key_here
VERTEXAI_PROJECT=your-gcp-project
VERTEXAI_LOCATION=europe-west1
GEMINI_MODEL=gemini-2.5-flash
GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
```

## Architecture

### Multi-Stage Build
1. **Builder stage**: Elixir + Node.js for compiling assets and creating release
2. **Runtime stage**: Minimal Alpine Linux with only runtime dependencies

### Security Features
- Non-root user execution (UID/GID 1000)
- Minimal attack surface (no build tools in runtime)
- Health checks for container orchestration
- Volume mounts for persistent data

### Performance Optimizations
- Optimized layer caching (dependencies installed before source code)
- Multi-stage builds reduce final image size by ~70%
- Asset pre-compilation for faster startup
- Proper instruction ordering for build cache efficiency

## Persistent Data

The application uses volumes for persistent storage:

- `/app/priv/chat_logs` - Chat conversation history
- `/app/priv/uploads` - User uploaded files
- `/app/priv/data` - Application data and tags

## Production Deployment

### Cloud Platform Deployment

#### Google Cloud Run
```bash
# Build and push to Google Container Registry
docker build -t gcr.io/your-project/live-ai-chat .
docker push gcr.io/your-project/live-ai-chat

# Deploy to Cloud Run
gcloud run deploy live-ai-chat \
  --image gcr.io/your-project/live-ai-chat \
  --platform managed \
  --region europe-west1 \
  --allow-unauthenticated \
  --set-env-vars PHX_SERVER=true,SECRET_KEY_BASE=$SECRET_KEY_BASE
```

#### Kubernetes
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: live-ai-chat
spec:
  replicas: 2
  selector:
    matchLabels:
      app: live-ai-chat
  template:
    metadata:
      labels:
        app: live-ai-chat
    spec:
      containers:
      - name: app
        image: your-registry/live-ai-chat:latest
        ports:
        - containerPort: 3000
        env:
        - name: PHX_SERVER
          value: "true"
        - name: SECRET_KEY_BASE
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: secret-key-base
        volumeMounts:
        - name: data-volume
          mountPath: /app/priv
      volumes:
      - name: data-volume
        persistentVolumeClaim:
          claimName: app-data-pvc
```

## Troubleshooting

### Common Issues

#### Container won't start
```bash
# Check logs
docker logs <container-id>

# Common causes:
# - Missing SECRET_KEY_BASE
# - Invalid Google Cloud credentials
# - Port conflicts
```

#### Assets not loading
```bash
# Rebuild with no cache
docker build --no-cache -t your-image .

# Check asset compilation
docker run --rm your-image ls -la /app/priv/static/
```

#### Permission errors
```bash
# Check file ownership in volumes
docker run --rm -v chat_logs:/data alpine ls -la /data

# Fix permissions
docker run --rm -v chat_logs:/data alpine chown -R 1000:1000 /data
```

### Health Checks

The container includes health checks accessible via:
```bash
# Docker
docker inspect <container-id> | grep -A 10 Health

# Docker Compose
docker-compose ps
```

## Development

### Local Development with Docker
```bash
# Run in development mode (mounts source)
docker-compose -f docker-compose.dev.yml up

# Access shell in running container
docker exec -it <container-name> /bin/sh

# Run tests in container
docker exec -it <container-name> mix test
```

### Build Performance Tips
- Use `.dockerignore` to exclude unnecessary files
- Order Dockerfile instructions by change frequency
- Use multi-stage builds to reduce final image size
- Leverage BuildKit for parallel builds

## Monitoring

### Metrics and Logs
- Application logs: `docker logs <container-id>`
- Health status: `/health` endpoint (if implemented)
- Metrics: Phoenix LiveDashboard at `/dashboard`

### Resource Usage
```bash
# Monitor container resources
docker stats

# Check disk usage of volumes
docker system df -v
```
