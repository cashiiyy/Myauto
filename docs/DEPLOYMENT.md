# Deployment Guide

The MyAuto backend is deployed via Docker Compose on an Ubuntu server (Tailscale IP: `100.89.251.123`).

## Prerequisites

- Docker and Docker Compose installed on the host.
- Tailscale installed and authenticated (for private network access).
- Firebase Admin SDK credentials (`firebase-adminsdk.json`).

## Services

- `api`: FastAPI application (Port 8000).
- `redis`: Redis server (Port 6379, not exposed publicly).
- `db`: PostgreSQL database (Port 5432, not exposed publicly).

## Configuration

1. Create a `.env` file in the `backend` directory (do not commit to git):

```env
DATABASE_URL=postgresql://myauto:myauto_dev_pw@db:5432/myauto
REDIS_URL=redis://redis:6379/0
ENVIRONMENT=production
CORS_ORIGINS="*"
```

2. Place `firebase-adminsdk.json` in `backend/app/auth/`.

## Deploying

1. SSH into the server over Tailscale:
   ```bash
   ssh user@100.89.251.123
   ```

2. Navigate to the `backend` folder and bring up the stack:
   ```bash
   docker-compose up -d --build
   ```

3. View logs:
   ```bash
   docker-compose logs -f api
   ```

## Nginx Reverse Proxy (Future)

For production without Tailscale, set up Nginx with SSL:
```nginx
server {
    listen 443 ssl;
    server_name api.myauto.app;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /ws {
        proxy_pass http://localhost:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
    }
}
```
