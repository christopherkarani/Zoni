# Zoni Deployment Guide

This guide covers deployment strategies for Zoni RAG server applications using Vapor and Hummingbird frameworks.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Security Checklist](#security-checklist)
- [Vapor Deployment](#vapor-deployment)
- [Hummingbird Deployment](#hummingbird-deployment)
- [Production Configuration](#production-configuration)
- [Monitoring & Observability](#monitoring--observability)
- [Scaling Strategies](#scaling-strategies)

## Prerequisites

- Swift 6.0 or later
- macOS 14+ / Linux (Ubuntu 22.04+ recommended)
- PostgreSQL 14+ (for production tenant storage)
- Redis (optional, for distributed caching)
- Apple Silicon (M1/M2/M3/M4) if using ZoniApple MLX features

## Security Checklist

Before deploying to production, ensure you've addressed these critical security items:

### ⚠️ CRITICAL - Must Fix Before Production

1. **API Key Hashing**
   - ❌ **DO NOT** use `TenantManager.hashApiKey()` - it's deprecated and insecure
   - ✅ Use bcrypt, Argon2id, or scrypt with salt and work factor ≥12
   - See: `Sources/ZoniServer/MultiTenancy/TenantManager.swift:465-518`

2. **JWT Secret Configuration**
   - ❌ **NEVER** set `jwtSecret: nil` in production
   - ✅ Always provide a secret ≥32 bytes stored in environment variables
   - ✅ Rotate secrets periodically using a key management system
   - See: `Sources/ZoniServer/MultiTenancy/TenantManager.swift:87-130`

3. **HTTPS/TLS**
   - ✅ Always use HTTPS in production
   - ✅ Use TLS 1.3 with strong cipher suites
   - ✅ Implement certificate pinning for mobile clients

4. **Rate Limiting**
   - ✅ Apply rate limiting to all public endpoints
   - ✅ Configure per-tenant limits based on subscription tier
   - ✅ Monitor and alert on rate limit violations

## Vapor Deployment

### Basic Setup

```swift
import Vapor
import ZoniVapor
import ZoniServer

@main
struct Application {
    static func main() async throws {
        var env = try Environment.detect()
        let app = Application(env)
        defer { app.shutdown() }

        // Configure Zoni
        try await configureZoni(app)

        // Run
        try await app.run()
    }
}

func configureZoni(_ app: Application) async throws {
    // 1. Validate JWT secret
    guard let jwtSecret = Environment.get("JWT_SECRET"),
          jwtSecret.count >= 32 else {
        app.logger.critical("JWT_SECRET must be set and ≥32 bytes")
        throw Abort(.internalServerError)
    }

    // 2. Initialize tenant storage (PostgreSQL)
    let postgresConfig = SQLPostgresConfiguration(
        hostname: Environment.get("DB_HOST") ?? "localhost",
        port: Environment.get("DB_PORT").flatMap(Int.init) ?? 5432,
        username: Environment.get("DB_USER") ?? "zoni",
        password: Environment.get("DB_PASSWORD") ?? "",
        database: Environment.get("DB_NAME") ?? "zoni",
        tls: .prefer(try .init(configuration: .clientDefault))
    )

    app.databases.use(.postgres(configuration: postgresConfig), as: .psql)

    // 3. Initialize Zoni configuration
    let config = ZoniVaporConfiguration(
        tenantStorage: PostgresTenantStorage(database: app.db),
        jwtSecret: jwtSecret,
        rateLimitPolicy: ProductionRateLimitPolicy(),
        maxConcurrentJobs: Environment.get("MAX_JOBS").flatMap(Int.init) ?? 8
    )

    // 4. Configure routes with middleware
    let protected = app.grouped(TenantMiddleware())
    try routes(protected, config: config)
}

func routes(_ app: RoutesBuilder, config: ZoniVaporConfiguration) throws {
    // Health check (no auth required)
    app.get("health", use: HealthController().status)

    // Protected routes
    let v1 = app.grouped("api", "v1")

    // Query endpoints
    v1.post("query", use: QueryController(config: config).query)

    // Ingest endpoints
    v1.post("ingest", use: IngestController(config: config).ingest)

    // Job management
    v1.get("jobs", ":id", use: JobController(config: config).status)
}
```

### Environment Variables

Create a `.env` file for development (never commit to git):

```bash
# JWT Configuration
JWT_SECRET=your-32-byte-or-longer-secret-here-change-in-production

# Database Configuration
DB_HOST=localhost
DB_PORT=5432
DB_USER=zoni
DB_PASSWORD=secure-password-here
DB_NAME=zoni_production

# Server Configuration
SERVER_PORT=8080
SERVER_HOSTNAME=0.0.0.0
LOG_LEVEL=info

# Job System
MAX_JOBS=8
JOB_POLL_INTERVAL=1

# Rate Limiting
RATE_LIMIT_ENABLED=true
```

### Docker Deployment

```dockerfile
# Dockerfile
FROM swift:6.0-jammy as builder

WORKDIR /app
COPY . .

RUN swift build -c release --static-swift-stdlib

FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    libssl3 \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/.build/release/YourApp .

EXPOSE 8080

CMD ["./YourApp", "serve", "--hostname", "0.0.0.0", "--port", "8080"]
```

```yaml
# docker-compose.yml
version: '3.8'

services:
  app:
    build: .
    ports:
      - "8080:8080"
    environment:
      - JWT_SECRET=${JWT_SECRET}
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_USER=zoni
      - DB_PASSWORD=${DB_PASSWORD}
      - DB_NAME=zoni
    depends_on:
      - postgres
    restart: unless-stopped

  postgres:
    image: postgres:16-alpine
    environment:
      - POSTGRES_USER=zoni
      - POSTGRES_PASSWORD=${DB_PASSWORD}
      - POSTGRES_DB=zoni
    volumes:
      - postgres-data:/var/lib/postgresql/data
    restart: unless-stopped

volumes:
  postgres-data:
```

### Kubernetes Deployment

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zoni-api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: zoni-api
  template:
    metadata:
      labels:
        app: zoni-api
    spec:
      containers:
      - name: zoni
        image: your-registry/zoni:latest
        ports:
        - containerPort: 8080
        env:
        - name: JWT_SECRET
          valueFrom:
            secretKeyRef:
              name: zoni-secrets
              key: jwt-secret
        - name: DB_HOST
          value: postgres-service
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: zoni-secrets
              key: db-password
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "2000m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: zoni-api
spec:
  type: LoadBalancer
  selector:
    app: zoni-api
  ports:
  - port: 443
    targetPort: 8080
    protocol: TCP
```

## Hummingbird Deployment

### Basic Setup

```swift
import Hummingbird
import ZoniHummingbird
import ZoniServer

@main
struct Application {
    static func main() async throws {
        // 1. Validate security configuration
        guard let jwtSecret = Environment.get("JWT_SECRET"),
              jwtSecret.count >= 32 else {
            fatalError("JWT_SECRET must be set and ≥32 bytes")
        }

        // 2. Create Zoni configuration
        let config = ZoniHummingbirdConfiguration(
            tenantStorage: PostgresTenantStorage(...),
            jwtSecret: jwtSecret,
            rateLimitPolicy: ProductionRateLimitPolicy(),
            maxConcurrentJobs: 8
        )

        // 3. Build application
        let app = try await buildApplication(config: config)

        // 4. Run
        try await app.run()
    }

    static func buildApplication(config: ZoniHummingbirdConfiguration) async throws -> some ApplicationProtocol {
        let router = Router()

        // Health check
        router.get("/health") { request, context in
            return HealthResponse(status: "ok")
        }

        // Protected API routes
        router.group("/api/v1")
            .add(middleware: TenantMiddleware(config: config))
            .add(middleware: RateLimitMiddleware(config: config))
            .post("/query", use: QueryRoutes.query)
            .post("/ingest", use: IngestRoutes.ingest)

        return Application(router: router, configuration: .init())
    }
}
```

## Production Configuration

### Logging

Configure structured logging for production:

```swift
import Logging

// Configure at app startup
LoggingSystem.bootstrap { label in
    var handler = StreamLogHandler.standardOutput(label: label)
    handler.logLevel = .info
    return handler
}

// In production, use a centralized logging system:
LoggingSystem.bootstrap { label in
    // Example: DataDog, CloudWatch, Splunk integration
    YourCloudLoggingHandler(label: label)
}
```

### Database Connection Pool

```swift
// Vapor
app.databases.use(.postgres(
    configuration: postgresConfig,
    maxConnectionsPerEventLoop: 4
), as: .psql)

// PostgresNIO directly
let pool = EventLoopGroupConnectionPool(
    source: PostgresConnectionSource(configuration: postgresConfig),
    maxConnections: 16,
    on: app.eventLoopGroup
)
```

### Rate Limiting Policy

```swift
struct ProductionRateLimitPolicy: TenantRateLimitPolicy {
    func limits(for tier: String) -> RateLimits {
        switch tier {
        case "free":
            return RateLimits(
                requestsPerMinute: 60,
                requestsPerHour: 1000,
                concurrentRequests: 5
            )
        case "pro":
            return RateLimits(
                requestsPerMinute: 600,
                requestsPerHour: 10000,
                concurrentRequests: 20
            )
        case "enterprise":
            return RateLimits(
                requestsPerMinute: 6000,
                requestsPerHour: 100000,
                concurrentRequests: 100
            )
        default:
            return RateLimits(
                requestsPerMinute: 10,
                requestsPerHour: 100,
                concurrentRequests: 2
            )
        }
    }
}
```

## Monitoring & Observability

### Health Checks

Implement comprehensive health checks:

```swift
struct HealthCheck {
    let database: Database
    let jobQueue: JobQueueBackend

    func check() async -> HealthStatus {
        var status = HealthStatus()

        // Check database
        do {
            _ = try await database.query("SELECT 1").first()
            status.database = .healthy
        } catch {
            status.database = .unhealthy(error)
        }

        // Check job queue
        status.jobQueue = await checkJobQueue()

        return status
    }
}
```

### Metrics (Prometheus Integration)

```swift
// Add swift-prometheus dependency
import Prometheus

let requestCounter = Counter(
    name: "zoni_requests_total",
    helpText: "Total number of requests",
    labels: ["endpoint", "method", "status"]
)

let requestDuration = Histogram(
    name: "zoni_request_duration_seconds",
    helpText: "Request duration in seconds",
    labels: ["endpoint"]
)

// Middleware to record metrics
struct MetricsMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let start = Date()
        let response = try await next.respond(to: request)
        let duration = Date().timeIntervalSince(start)

        requestCounter.inc(
            1,
            ["endpoint": request.url.path, "method": request.method.rawValue, "status": "\(response.status.code)"]
        )
        requestDuration.observe(duration, ["endpoint": request.url.path])

        return response
    }
}
```

## Scaling Strategies

### Horizontal Scaling

- **Stateless Design**: All state in PostgreSQL/Redis, not in-memory
- **Load Balancer**: Use NGINX, AWS ALB, or similar
- **Session Affinity**: Not required due to stateless design
- **Database**: Use read replicas for query endpoints

### Job Queue Scaling

```swift
// Option 1: Dedicated job workers
// Run multiple instances with job executor only
let executor = JobExecutor(
    queue: postgresJobQueue,
    services: services,
    maxConcurrentJobs: 16  // Tune based on CPU cores
)
await executor.start()

// Option 2: Distributed queue (Redis-backed)
// For multi-instance deployments
let redisQueue = RedisJobQueue(redis: redisPool)
```

### Caching Strategy

```swift
// Layer 1: In-memory cache (per instance)
let tenantManager = TenantManager(
    storage: storage,
    jwtSecret: secret,
    cacheTTL: .minutes(5),
    maxCacheSize: 10_000
)

// Layer 2: Distributed cache (Redis)
// For tenant data shared across instances
let redisCache = RedisCache(redis: redisPool)
```

## Troubleshooting

### Common Issues

**Issue**: Jobs not processing
- Check: `JobExecutor.isProcessing` status
- Check: Database connectivity from executor
- Check: Job queue has pending jobs

**Issue**: High memory usage
- Check: Tenant cache size (`TenantManager.cacheCount`)
- Check: Job executor concurrency limit
- Check: Vector store query result size limits

**Issue**: Slow queries
- Check: Database indexes on tenant_id, status, created_at
- Check: PostgreSQL query plan (`EXPLAIN ANALYZE`)
- Check: Vector store index configuration

## Support

For issues and questions:
- GitHub Issues: https://github.com/christopherkarani/Zoni/issues
- Documentation: See README.md and inline documentation
