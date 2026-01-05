# Zoni Performance Optimization Guide

This document outlines current performance characteristics and optimization opportunities in the Zoni codebase.

## Current Performance Profile

### Cache Eviction (TenantManager)

**Current Implementation**: O(n log n) eviction using full cache sort

**Location**: `Sources/ZoniServer/MultiTenancy/TenantManager.swift:371-384`

```swift
private func evictCacheIfNeeded() {
    guard cache.count > maxCacheSize else { return }

    let targetRemovalCount = max(1, maxCacheSize / 10)

    // O(n log n) - sorts entire cache on every eviction
    let sortedByAge = cache.sorted { $0.value.lastAccessed < $1.value.lastAccessed }
    let keysToRemove = sortedByAge.prefix(targetRemovalCount).map { $0.key }

    for key in keysToRemove {
        cache.removeValue(forKey: key)
    }
}
```

**Performance Characteristics**:
- Eviction triggered when cache exceeds `maxCacheSize` (default: 10,000 entries)
- Removes 10% of cache (1,000 entries) per eviction cycle
- **Time Complexity**: O(n log n) where n = cache size
- **Memory**: O(n) for sorted array
- **Frequency**: Every ~1,000 cache insertions (with default settings)

**Impact Analysis**:
- With default maxCacheSize=10,000: ~0.5-2ms per eviction on modern hardware
- Eviction is synchronous and blocks tenant resolution during execution
- Impact increases linearly with cache size

**Optimization Options**:

#### Option 1: Min-Heap Based LRU (Recommended for Large Deployments)

```swift
// Use a min-heap to track oldest entries
// Time complexity: O(log n) for eviction
// Space complexity: O(n)

import Collections  // Swift Collections package

private var cache: [String: CachedTenant] = [:]
private var lruHeap: Heap<CacheEntry> = []  // Min-heap sorted by lastAccessed

private func evictCacheIfNeeded() {
    guard cache.count > maxCacheSize else { return }

    let targetRemovalCount = max(1, maxCacheSize / 10)

    for _ in 0..<targetRemovalCount {
        guard let oldest = lruHeap.popMin() else { break }
        cache.removeValue(forKey: oldest.key)
    }
}
```

**Benefits**:
- O(log n) eviction vs O(n log n)
- 10-100x faster for large caches
- Predictable performance

**Tradeoffs**:
- Additional dependency (swift-collections)
- More complex implementation
- Heap maintenance overhead on every cache access

#### Option 2: Segmented LRU Cache

```swift
// Divide cache into hot/cold segments
// Only sort cold segment on eviction

private var hotCache: [String: CachedTenant] = [:]  // Recently accessed
private var coldCache: [String: CachedTenant] = [:]  // Less frequently accessed

private func evictCacheIfNeeded() {
    // Promote from cold to hot on access
    // Only sort and evict from cold segment
    let sortedCold = coldCache.sorted { $0.value.lastAccessed < $1.value.lastAccessed }
    // ... evict from sortedCold
}
```

**Benefits**:
- Amortized O(n/k log n/k) where k = number of segments
- No external dependencies
- Simple to understand

**Tradeoffs**:
- More complex cache management
- Tuning required (segment sizes)

#### Option 3: Approximate LRU with Sampling

```swift
// Sample random subset of cache instead of sorting all entries
// Trade accuracy for speed

private func evictCacheIfNeeded() {
    guard cache.count > maxCacheSize else { return }

    let sampleSize = min(1000, cache.count)  // Sample 1000 random entries
    let sample = cache.shuffled().prefix(sampleSize)
    let sorted = sample.sorted { $0.value.lastAccessed < $1.value.lastAccessed }

    let targetRemovalCount = max(1, maxCacheSize / 10)
    let keysToRemove = sorted.prefix(targetRemovalCount).map { $0.key }

    for key in keysToRemove {
        cache.removeValue(forKey: key)
    }
}
```

**Benefits**:
- O(k log k) where k = sample size (constant)
- No external dependencies
- Simple implementation

**Tradeoffs**:
- Less accurate LRU (may not evict truly oldest)
- Still needs tuning

#### Recommendation

For most deployments, the **current O(n log n) implementation is sufficient**:
- Eviction happens infrequently (every ~1,000 insertions)
- 10,000 entry cache with 10% eviction = ~1ms overhead
- Overhead amortized across 1,000 cache hits (0.001ms per hit)

**When to optimize**:
- Cache size > 50,000 entries
- High tenant churn (frequent cache evictions)
- Strict latency requirements (p99 < 10ms)

**Implementation Priority**: Low (optimize only if profiling shows this as bottleneck)

## Job Queue Performance

### Current Implementation

**Backend**: In-memory queue with array-based priority queue

**Location**: `Sources/ZoniServer/Jobs/InMemoryJobQueue.swift`

**Performance Characteristics**:
- Enqueue: O(n) worst case (inserts in priority order)
- Dequeue: O(1) (removes from front)
- Status update: O(1) (dictionary lookup)

**Optimization Opportunities**:

#### For High-Volume Deployments

Replace in-memory queue with PostgreSQL or Redis:

```swift
// PostgreSQL-backed queue with proper indexing
CREATE INDEX idx_jobs_pending ON jobs(status, priority DESC, created_at)
WHERE status = 'pending';

// Redis-backed queue with sorted sets
ZADD jobs:pending {priority} {job_id}
```

**Benefits**:
- Persistent (survives restarts)
- Distributed (multiple workers)
- Scales beyond single machine memory

## Vector Search Performance

### Optimization Checklist

- [ ] **Indexes**: Ensure vector columns have HNSW or IVFFlat indexes
- [ ] **Query Planning**: Use `EXPLAIN ANALYZE` to verify index usage
- [ ] **Batch Queries**: Use `concurrentMap` for parallel queries
- [ ] **Result Limits**: Always limit result set size (default: 10-20 documents)
- [ ] **Caching**: Cache frequent queries at application level

### SQLite Vector Store

**Current**: Full table scan with in-memory distance calculation

**Optimization**: Add vector index using sqlite-vss extension

```sql
-- Install sqlite-vss extension
CREATE VIRTUAL TABLE vec_index USING vss0(
    embedding(384)  -- dimension
);

-- Index creation ~100ms for 10k vectors
```

## Concurrency Tuning

### Job Executor

**Default**: 4 concurrent jobs

**Tuning Guide**:
```swift
// CPU-bound jobs (embeddings, ML inference)
maxConcurrentJobs = ProcessInfo.processInfo.processorCount

// I/O-bound jobs (web scraping, API calls)
maxConcurrentJobs = ProcessInfo.processInfo.processorCount * 2

// Memory-bound jobs (large document processing)
maxConcurrentJobs = min(4, ProcessInfo.processInfo.processorCount)
```

### Database Connections

**Vapor Default**: 4 connections per event loop

**Recommended**:
```swift
// Formula: (CPU cores * 2) + effective_spindle_count
// For cloud databases: 10-20 connections per instance
app.databases.use(.postgres(
    configuration: config,
    maxConnectionsPerEventLoop: 4  // Tune based on load testing
), as: .psql)
```

## Memory Optimization

### Cache Sizing

**TenantManager Cache**:
- Default: 10,000 tenants
- Memory: ~500KB - 2MB (depending on config size)
- Recommendation: Size to fit working set (active tenants in 5-minute window)

**Vector Store Cache**:
- Consider external cache (Redis) for multi-instance deployments
- Size based on query result frequency

## Monitoring & Profiling

### Key Metrics to Track

```swift
import Prometheus

// Cache efficiency
let cacheHitRate = Gauge(name: "zoni_cache_hit_rate")
let cacheEvictionCount = Counter(name: "zoni_cache_evictions_total")

// Job queue health
let jobQueueDepth = Gauge(name: "zoni_job_queue_depth")
let jobProcessingTime = Histogram(name: "zoni_job_duration_seconds")

// Query performance
let queryDuration = Histogram(name: "zoni_query_duration_seconds")
let queryResultSize = Histogram(name: "zoni_query_results")
```

### Profiling Tools

**Development**:
- Instruments (macOS): Time Profiler, Allocations
- `swift build -c release` for realistic performance testing

**Production**:
- SwiftLog with structured logging
- APM tools: DataDog, New Relic, Honeycomb
- Database slow query logs

## Benchmarking

### Before Optimization

Always benchmark current performance:

```swift
import XCTest

func testCacheEvictionPerformance() {
    measure {
        // Benchmark code here
    }
}
```

### Performance Targets

- **Tenant Resolution**: < 5ms (p95)
- **Query Execution**: < 100ms (p95)
- **Job Processing**: Based on job type
- **Cache Eviction**: < 2ms (p99)

## Future Optimizations

### Low Priority (Premature Optimization)

These optimizations are documented but **should not be implemented** until profiling shows they're necessary:

1. **Cache Eviction Algorithm**: Currently O(n log n), optimize if cache > 50k entries
2. **Job Queue Data Structure**: Currently array-based, optimize for > 10k pending jobs
3. **Tenant Resolution Batching**: Batch multiple tenant lookups (needs API changes)

### When to Optimize

Follow this decision tree:
1. Is there a measurable performance problem? (User complaints, SLA violations)
2. Have you profiled and identified the bottleneck?
3. Will the optimization provide ≥2x improvement?
4. Is the complexity increase justified?

If all answers are "yes", proceed with optimization. Otherwise, focus on features.

## Support

For performance questions:
- Profile first, optimize second
- Share profiling data when reporting performance issues
- Consider vertical scaling (larger instance) before horizontal scaling
