# Vault Progress Server

Docker nginx container to serve progress files with proper CORS headers.

## Quick Start

```bash
# Start the server
./start.sh

# Stop the server
./stop.sh
```

## Access Points

- **Progress Dashboard**: http://localhost:8080/progress.html
- **Progress JSON API**: http://localhost:8080/progress.json

## Features

- ✅ Proper CORS headers for cross-origin requests
- ✅ No-cache headers for real-time progress updates
- ✅ Gzip compression for better performance
- ✅ Security headers
- ✅ Health checks
- ✅ Auto-restart on failure

## Configuration

The nginx server serves files from `/Users/mlautenschlager/cloudya/vault/` with:
- Port 8080 exposed
- CORS enabled for all origins
- No-cache for progress files
- Proper MIME types

## Docker Commands

```bash
# Manual start
docker-compose up -d

# Manual stop
docker-compose down

# View logs
docker-compose logs -f

# Check status
docker-compose ps
```

## Troubleshooting

1. **Port 8080 already in use**: Stop other services using port 8080
2. **Files not found**: Ensure progress.json and progress.html exist in vault directory
3. **Docker not running**: Start Docker Desktop first

## CORS Headers

The server includes these CORS headers:
- `Access-Control-Allow-Origin: *`
- `Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE`
- `Access-Control-Allow-Headers: DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization`