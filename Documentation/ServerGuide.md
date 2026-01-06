# Server Deployment Guide

## Overview

Zoni provides first-class support for server-side Swift deployments with production-ready integrations for the two leading server frameworks:

- **ZoniServer** - Core server-side abstractions including multi-tenancy, job queues, and DTOs
- **ZoniVapor** - Complete Vapor framework integration with REST endpoints and WebSocket support
- **ZoniHummingbird** - Hummingbird framework integration with modern async patterns

All server components are built with Swift 6 strict concurrency checking, ensuring thread-safe operations and predictable performance under load.

## Installation

### Package.swift

Add Zoni to your package dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/user/Zoni", from: "1.0.0")
]
```

### Target Dependencies

Choose your framework and add the appropriate dependencies:

```swift
targets: [
    .target(
        name: "App",
        dependencies: [
            "Zoni",
            "ZoniServer",
            "ZoniVapor",  // or "ZoniHummingbird"
        ]
    )
]
```

## Vapor Integration

### Basic Setup

Configure Zoni in your Vapor application's `configure.swift`:

```swift
import Vapor
import Zoni
import ZoniVapor
import ZoniServer

func configure(_ app: Application) async throws {
    // 1. Create the query engine with your chosen services
    let vectorStore = try await PgVectorStore.connect(
        connectionString: Environment.get("DATABASE_URL")!,
        configuration: PgVectorStore.Configuration(
            tableName: "zoni_chunks",
            dimensions: 1536,
            indexType: .ivfflat
        ),
        eventLoopGroup: app.eventLoopGroup
    )

    let embedder = OpenAIEmbedder(
        apiKey: Environment.get("OPENAI_API_KEY")!,
        model: .textEmbedding3Small
    )

    let llm = AnthropicLLM(
        apiKey: Environment.get("ANTHROPIC_API_KEY")!,
        model: "claude-sonnet-4-20250514"
    )

    let queryEngine = QueryEngine(
        vectorStore: vectorStore,
        embedder: embedder,
        llm: llm
    )

    // 2. Setup multi-tenancy (optional)
    let tenantManager = TenantManager(
        storage: PostgresTenantStorage(connectionString: Environment.get("DATABASE_URL")!)
    )

    // 3. Create Zoni configuration
    let zoniConfig = ZoniVaporConfiguration(
        queryEngine: queryEngine,
        tenantManager: tenantManager,
        rateLimiter: TenantRateLimiter(),
        jobQueue: InMemoryJobQueue()
    )

    // 4. Configure Zoni services
    app.configureZoni(zoniConfig)

    // 5. Register RAG routes
    try app.registerZoniRoutes()
}
```

### Available Endpoints

After registration, the following REST endpoints are available at `/api/v1`:

#### Query Endpoints

- `POST /api/v1/query` - Execute a RAG query with LLM generation
- `GET /api/v1/query/retrieve?q=<query>&limit=<count>` - Search only (no generation)

#### Document Endpoints

- `POST /api/v1/documents` - Ingest documents (sync or async)
- `POST /api/v1/documents/batch` - Batch ingest (always async)
- `DELETE /api/v1/documents/:id` - Delete a document

#### Index Management

- `GET /api/v1/indices` - List all indices
- `POST /api/v1/indices` - Create a new index
- `GET /api/v1/indices/:name` - Get index information
- `DELETE /api/v1/indices/:name` - Delete an index

#### Job Management

- `GET /api/v1/jobs` - List jobs
- `GET /api/v1/jobs/:id` - Get job status
- `DELETE /api/v1/jobs/:id` - Cancel a job

#### Health Checks

- `GET /api/v1/health` - Basic health check
- `GET /api/v1/health/ready` - Readiness probe (for load balancers)

### Request Examples

#### Execute a Query

```bash
curl -X POST http://localhost:8080/api/v1/query \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What is Swift concurrency?",
    "options": {
      "retrievalLimit": 5,
      "temperature": 0.7,
      "filter": {
        "type": "equals",
        "field": "category",
        "value": "documentation"
      }
    }
  }'
```

Response:

```json
{
  "answer": "Swift concurrency provides structured concurrency with async/await...",
  "sources": [
    {
      "id": "chunk-123",
      "content": "Swift's async/await syntax...",
      "score": 0.92,
      "documentId": "doc-456",
      "source": "swift-guide.md"
    }
  ],
  "metadata": {
    "retrievalTimeMs": 45.2,
    "generationTimeMs": 1250.5,
    "totalTimeMs": 1295.7
  }
}
```

#### Ingest Documents

```bash
curl -X POST http://localhost:8080/api/v1/documents \
  -H "Authorization: ApiKey sk-abc123" \
  -H "Content-Type: application/json" \
  -d '{
    "documents": [
      {
        "content": "Swift is a powerful programming language...",
        "source": "swift-guide.md",
        "title": "Swift Programming Guide",
        "metadata": {
          "category": { "type": "string", "value": "documentation" },
          "rating": { "type": "double", "value": 4.5 }
        }
      }
    ],
    "options": {
      "chunkSize": 512,
      "chunkOverlap": 50,
      "async": true
    }
  }'
```

## Hummingbird Integration

### Basic Setup

```swift
import Hummingbird
import HummingbirdAuth
import Zoni
import ZoniHummingbird
import ZoniServer

@main
struct App {
    static func main() async throws {
        // 1. Create services (same as Vapor example)
        let queryEngine = QueryEngine(...)
        let tenantManager = TenantManager(...)

        let services = ZoniServices(
            queryEngine: queryEngine,
            tenantManager: tenantManager,
            rateLimiter: TenantRateLimiter(),
            jobQueue: InMemoryJobQueue()
        )

        // 2. Create router with RAG context
        let router = Router(context: RAGRequestContext.self)

        // 3. Add all Zoni routes
        addZoniRoutes(to: router, services: services)

        // 4. Create and run application
        let app = Application(
            router: router,
            configuration: .init(address: .hostname("0.0.0.0", port: 8080))
        )

        try await app.runService()
    }
}
```

### Middleware Stack

Hummingbird integration includes:

- **TenantMiddleware** - Resolves tenant context from Authorization header
- **RateLimitMiddleware** - Per-tenant rate limiting with token bucket algorithm
- **ErrorMiddleware** - Standardized error responses

## PostgreSQL with pgvector

### Database Setup

```sql
-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Create chunks table (done automatically by Zoni)
CREATE TABLE zoni_chunks (
    id TEXT PRIMARY KEY,
    content TEXT NOT NULL,
    embedding vector(1536),
    document_id TEXT NOT NULL,
    chunk_index INTEGER NOT NULL,
    start_offset INTEGER DEFAULT 0,
    end_offset INTEGER DEFAULT 0,
    source TEXT,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for performance
CREATE INDEX ON zoni_chunks (document_id);
CREATE INDEX ON zoni_chunks USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);
```

### Configuration

```swift
let vectorStore = try await PgVectorStore.connect(
    connectionString: "postgres://user:pass@localhost:5432/db",
    configuration: PgVectorStore.Configuration(
        tableName: "zoni_chunks",
        dimensions: 1536,  // Must match embedding model
        indexType: .ivfflat,
        ivfflatLists: 100  // sqrt(rows) to rows/1000
    ),
    eventLoopGroup: eventLoopGroup
)
```

### Index Selection Guide

Choose the right index type for your workload:

| Index Type | Build Time | Search Speed | Recall | Best For |
|------------|-----------|--------------|--------|----------|
| **None** | Instant | Slow (O(n)) | 100% | < 10k vectors |
| **IVFFlat** | Fast | Good | ~95% | Frequent updates, < 1M vectors |
| **HNSW** | Slow | Excellent | ~99% | Read-heavy, large datasets |

### Embedding Model Dimensions

Common embedding models and their dimensions:

- OpenAI `text-embedding-3-small`: **1536**
- OpenAI `text-embedding-3-large`: **3072**
- Cohere `embed-english-v3.0`: **1024**
- Sentence Transformers `all-MiniLM-L6-v2`: **384**

## Multi-Tenancy

### Tenant Storage

Implement `TenantStorage` protocol for your database:

```swift
import ZoniServer

actor PostgresTenantStorage: TenantStorage {
    private let pool: PostgresConnectionPool

    func findByApiKey(_ apiKey: String) async throws -> TenantContext? {
        let hashedKey = TenantManager.hashApiKey(apiKey)
        // Query database for tenant by hashed API key
        return try await pool.withConnection { connection in
            let rows = try await connection.query(
                "SELECT tenant_id, tier FROM tenants WHERE api_key_hash = $1",
                [hashedKey]
            )
            guard let row = rows.first else { return nil }
            return TenantContext(
                tenantId: row[0],
                tier: TenantTier(rawValue: row[1]) ?? .free
            )
        }
    }

    func find(tenantId: String) async throws -> TenantContext? {
        // Implementation
    }
}
```

### Tenant Configuration

```swift
let tenantManager = TenantManager(
    storage: PostgresTenantStorage(pool: pool),
    jwtSecret: Environment.get("JWT_SECRET"),
    cacheTTL: .minutes(5)
)
```

### Authentication Methods

Zoni supports three authentication formats:

#### 1. API Key Header

```bash
curl -H "Authorization: ApiKey sk-live-abc123" http://localhost:8080/api/v1/query
```

#### 2. Bearer Token (JWT)

```bash
curl -H "Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGc..." http://localhost:8080/api/v1/query
```

JWT payload must include `tenant_id`:

```json
{
  "tenant_id": "tenant_123",
  "sub": "user_456",
  "exp": 1704067200
}
```

#### 3. Raw API Key

```bash
curl -H "Authorization: sk-live-abc123" http://localhost:8080/api/v1/query
```

### Per-Tenant Rate Limiting

```swift
let rateLimiter = TenantRateLimiter()

// Configure limits by tier
await rateLimiter.setLimit(for: .free, requests: 10, per: .minute)
await rateLimiter.setLimit(for: .pro, requests: 100, per: .minute)
await rateLimiter.setLimit(for: .enterprise, requests: 1000, per: .minute)
```

## Asynchronous Job Processing

### Job Queue Setup

For production deployments, use a persistent job queue:

```swift
// In-memory queue (development only)
let jobQueue = InMemoryJobQueue()

// Redis queue (production)
// let jobQueue = RedisJobQueue(client: redisClient)
```

### Job Executor

```swift
let executor = JobExecutor(
    queue: jobQueue,
    services: services,
    maxConcurrentJobs: 4,
    pollInterval: .seconds(1)
)

// Start processing in background
Task {
    await executor.start()
}

// Graceful shutdown
await executor.stop()
```

### Submitting Jobs

```swift
// Submit ingestion job
let job = IngestJob(
    tenantId: "tenant-123",
    documents: documents,
    options: IngestOptions(chunkSize: 512, async: true)
)

let jobId = try await jobQueue.enqueue(job)
```

### Job Status Tracking

```bash
curl http://localhost:8080/api/v1/jobs/{jobId}
```

Response:

```json
{
  "jobId": "job-123",
  "status": "running",
  "progress": 0.45,
  "createdAt": "2024-01-15T10:30:00Z"
}
```

## WebSocket Streaming

### Vapor WebSocket Setup

```swift
import Vapor

app.webSocket("ws", "rag", "stream") { req, ws in
    ws.onText { ws, text in
        let request = try JSONDecoder().decode(QueryRequest.self, from: Data(text.utf8))

        // Stream query events
        let events = try await app.zoni.queryEngine.streamQuery(
            request.query,
            options: request.toQueryOptions()
        )

        for try await event in events {
            let dto = StreamEventDTO.from(event)
            let data = try JSONEncoder().encode(dto)
            try await ws.send(String(data: data, encoding: .utf8)!)
        }
    }
}
```

### Client Example

```javascript
const ws = new WebSocket('ws://localhost:8080/ws/rag/stream');

ws.onopen = () => {
  ws.send(JSON.stringify({
    query: "What is Swift concurrency?",
    options: { retrievalLimit: 5 }
  }));
};

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);

  switch (data.type) {
    case 'retrievalStarted':
      console.log('Searching documents...');
      break;
    case 'retrievalComplete':
      console.log('Found', data.data.length, 'sources');
      break;
    case 'generationChunk':
      process.stdout.write(data.data);
      break;
    case 'complete':
      console.log('\nDone!');
      break;
  }
};
```

## Docker Deployment

### Dockerfile

```dockerfile
# Build stage
FROM swift:6.0 as builder

WORKDIR /app

# Copy package manifest
COPY Package.swift Package.resolved ./

# Resolve dependencies
RUN swift package resolve

# Copy source code
COPY Sources ./Sources

# Build release binary
RUN swift build -c release --static-swift-stdlib

# Runtime stage
FROM swift:6.0-slim

WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/.build/release/App /app/App

# Expose port
EXPOSE 8080

# Run the app
CMD ["/app/App", "serve", "--hostname", "0.0.0.0", "--port", "8080"]
```

### Docker Compose

```yaml
version: '3.8'

services:
  app:
    build: .
    ports:
      - "8080:8080"
    environment:
      - DATABASE_URL=postgres://postgres:postgres@db:5432/zoni
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      - JWT_SECRET=${JWT_SECRET}
    depends_on:
      - db
      - redis
    restart: unless-stopped

  db:
    image: pgvector/pgvector:pg16
    environment:
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: zoni
    volumes:
      - pgdata:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    restart: unless-stopped

volumes:
  pgdata:
```

### Running with Docker

```bash
# Build and start services
docker-compose up -d

# View logs
docker-compose logs -f app

# Stop services
docker-compose down
```

## Kubernetes Deployment

### Deployment YAML

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zoni-server
spec:
  replicas: 3
  selector:
    matchLabels:
      app: zoni-server
  template:
    metadata:
      labels:
        app: zoni-server
    spec:
      containers:
      - name: app
        image: yourregistry/zoni-server:latest
        ports:
        - containerPort: 8080
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: zoni-secrets
              key: database-url
        - name: OPENAI_API_KEY
          valueFrom:
            secretKeyRef:
              name: zoni-secrets
              key: openai-api-key
        - name: ANTHROPIC_API_KEY
          valueFrom:
            secretKeyRef:
              name: zoni-secrets
              key: anthropic-api-key
        livenessProbe:
          httpGet:
            path: /api/v1/health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /api/v1/health/ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
---
apiVersion: v1
kind: Service
metadata:
  name: zoni-service
spec:
  selector:
    app: zoni-server
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
  type: LoadBalancer
```

## Performance Tuning

### Connection Pooling

For high-concurrency workloads, use connection pooling:

```swift
import PostgresNIO

let pool = PostgresConnectionSource(
    configuration: .init(
        host: "localhost",
        port: 5432,
        username: "postgres",
        password: "postgres",
        database: "zoni",
        tls: .prefer
    )
)

let poolConfig = PostgresConnectionPool.Configuration(
    minConnections: 2,
    maxConnections: 10
)

let connectionPool = PostgresConnectionPool(
    source: pool,
    configuration: poolConfig,
    eventLoop: eventLoop
)
```

### Rate Limiting Configuration

Tune rate limits based on your infrastructure:

```swift
// Aggressive limits for free tier
await rateLimiter.setLimit(for: .free, requests: 10, per: .minute)

// Generous limits for paying customers
await rateLimiter.setLimit(for: .pro, requests: 100, per: .minute)
await rateLimiter.setLimit(for: .enterprise, requests: 1000, per: .minute)

// Configure burst allowance
let limiter = TenantRateLimiter(
    maxBurst: 20  // Allow 20 requests in quick succession
)
```

### Job Executor Tuning

```swift
let executor = JobExecutor(
    queue: jobQueue,
    services: services,
    maxConcurrentJobs: 8,  // Increase for more powerful hardware
    pollInterval: .milliseconds(500)  // Poll more frequently
)
```

### PostgreSQL Optimization

```sql
-- Tune IVFFlat lists based on dataset size
-- Rule: sqrt(rows) to rows/1000
CREATE INDEX ON zoni_chunks USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 1000);  -- For ~1M rows

-- Set search precision (higher = better recall, slower)
SET ivfflat.probes = 10;  -- Default: 1

-- For HNSW, tune construction parameters
CREATE INDEX ON zoni_chunks USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

-- Tune search precision
SET hnsw.ef_search = 40;  -- Default: 40
```

### Monitoring

Track these metrics in production:

- Query latency (p50, p95, p99)
- Ingestion throughput
- Cache hit rate
- Job queue depth
- Database connection pool utilization
- Rate limit rejections

## Security Best Practices

### API Key Management

```swift
// Always hash API keys before storage
let hashedKey = TenantManager.hashApiKey(apiKey)

// Store only hashed keys in database
try await db.execute(
    "INSERT INTO tenants (api_key_hash) VALUES ($1)",
    hashedKey
)
```

### JWT Validation

```swift
let tenantManager = TenantManager(
    storage: storage,
    jwtSecret: Environment.get("JWT_SECRET")!,  // 256+ bit secret
    cacheTTL: .minutes(5)
)
```

### TLS/SSL Configuration

```swift
let store = try await PgVectorStore.connect(
    connectionString: connectionString,
    configuration: config,
    eventLoopGroup: eventLoopGroup,
    tlsMode: .require  // Require TLS in production
)
```

### Input Validation

All user inputs are validated server-side:

- Query length limits (max 1000 characters)
- Retrieval limit clamping (1-100)
- Metadata field name validation (alphanumeric + underscore only)
- SQL injection prevention via parameterized queries

## Troubleshooting

### Connection Issues

```swift
// Enable verbose logging
var logger = Logger(label: "zoni.server")
logger.logLevel = .debug
```

### pgvector Extension Missing

```bash
# Install pgvector on Ubuntu/Debian
sudo apt install postgresql-16-pgvector

# Install on macOS
brew install pgvector

# Verify installation
psql -d mydb -c "CREATE EXTENSION vector;"
```

### Rate Limiting Debug

```swift
// Check current limits
let usage = await rateLimiter.usage(for: tenant)
print("Used: \(usage.used) / \(usage.limit)")
```

## Next Steps

- **[Getting Started](GettingStarted.md)** - Quick start guide for new users
- **[Apple Platforms Guide](AppleGuide.md)** - iOS, macOS, and visionOS integration
- **[API Reference](API.md)** - Complete API documentation

## Additional Resources

- [Vapor Documentation](https://docs.vapor.codes/)
- [Hummingbird Documentation](https://docs.hummingbird.codes/)
- [pgvector GitHub](https://github.com/pgvector/pgvector)
- [PostgreSQL Performance Tuning](https://wiki.postgresql.org/wiki/Performance_Optimization)
