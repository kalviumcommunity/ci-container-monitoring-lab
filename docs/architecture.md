# Architecture

```
 developer commit
        │
        ▼
 GitHub Actions (CI)          .github/workflows/ci.yml
   install → test → build → smoke test
        │
        ▼
 Docker image                 Dockerfile
        │
        ▼
 docker compose up            docker-compose.yml
   ┌────────────┐   scrape    ┌──────────────┐   query   ┌──────────┐
   │    app     │◀────────────│  Prometheus  │◀──────────│ Grafana  │
   │ :8080      │  /metrics   │  :9090       │           │ :3000    │
   └────────────┘             └──────────────┘           └──────────┘
```

## Request / metrics flow

1. The app records a Prometheus counter and histogram for every HTTP request.
2. Prometheus scrapes the app's `/metrics` endpoint on a fixed interval.
3. Grafana queries Prometheus (its provisioned datasource) and renders the
   **Service Overview** dashboard.

## Ports

| Component  | In-container | Published on host |
|------------|--------------|-------------------|
| app        | 8080         | 8081              |
| Prometheus | 9090         | 9091              |
| Grafana    | 3000         | 3001              |

The app reads `PORT` from the environment and defaults to `8080` for the local lab stack.
