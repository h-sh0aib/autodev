# Docker PostgreSQL Port-Forward via Socat Sidecar

## Problem

PostgreSQL runs inside a Docker container, but port 5432 is not mapped to the host (`"5432/tcp -> []"` in `docker inspect`). You need localhost access for Prisma, psql, or application development, but you cannot recreate the container (user consent required for destructive ops like `docker stop && docker rm`).

## Solution

Run a sidecar `alpine/socat` container that forwards TCP traffic from the host to the PostgreSQL container over the Docker network.

```bash
# 1. Find the Docker network the postgres container is on
docker inspect <postgres-container> --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'

# 2. Run the socat forwarder
docker run -d --name pg-port-forward \
  --network <network_name> \
  -p 5432:5432 \
  alpine/socat TCP-LISTEN:5432,fork,reuseaddr TCP:<postgres_container_name>:5432
```

## Verification

```bash
# Check the container is running
docker ps --filter name=pg-port-forward --format "{{.Names}} {{.Status}} {{.Ports}}"
# Expected: pg-port-forward Up X minutes 0.0.0.0:5432->5432/tcp

# Test connectivity (from Docker network)
docker exec pg-port-forward sh -c "echo > /dev/tcp/<postgres_container>/5432 && echo OK"

# Test from host (requires psql)
psql -h localhost -U <user> -d <db> -c "SELECT 1;"
```

## Why This Works

- `alpine/socat` is ~5MB, pulls in seconds
- Uses TCP proxying — no PostgreSQL protocol awareness needed
- The `--network <name>` flag attaches the socat container to the same Docker network as postgres
- Container-to-container networking uses Docker's internal DNS (container name resolves)
- `-p 5432:5432` exposes the forwarded port to the host

## When NOT to Use

- If you CAN recreate the postgres container, just add `-p 5432:5432` to the original `docker run` or `docker-compose.yml` — that's cleaner
- If the postgres container already has a host port mapping that's just on a different port, use that port directly

## Cleanup

```bash
docker stop pg-port-forward && docker rm pg-port-forward
```

The forwarder is stateless — no data loss on removal.
