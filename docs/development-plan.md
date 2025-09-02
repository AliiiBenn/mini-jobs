# Mini-Jobs HTTP API Development Plan

## Project Overview

This document outlines the development plan to transform the mini-jobs Elixir project into a full-featured HTTP API job processing system. The goal is to create a robust, scalable job queue system with RESTful endpoints for job management.

## Architecture Overview

### Core Components

1. **HTTP Server Layer**
   - Cowboy HTTP server (NIF-based HTTP listener)
   - Custom Plug Router endpoint matching
   - Plug pipeline for request transformation
   - Direct Cowboy Req handlers for complex scenarios

2. **Request Processing Layer**
   - Plug.Conn abstraction layer
   - Custom Plug implementation (JSON parsing, validation, logging)
   - Request data transformation
   - Response formatting utilities

3. **Job Processing Core**
   - Job Queue Manager (FIFO queue)
   - Dynamic Worker Supervisor
   - Job Registry and State Management

4. **Persistence Layer**
   - ETS tables for in-memory state
   - Optional database integration
   - Backup and recovery mechanisms

5. **Monitoring & Observability**
   - Job status tracking
   - Metrics collection
   - Structured logging

### Detailed Request Flow

```
HTTP Request → Cowboy Transport Layer
     ↓
Cowboy Handler (MiniJobs.CowboyHandler)
     ↓
Plug.Conn creation from %CowboyReq{}
     ↓
Plug Router (route matching → Plug pipeline)
     ↓
Plug 1: MiniJobs.Plugs.JSONParser
     ↓
Plug 2: MiniJobs.Plugs.RequestValidator
     ↓
Plug 3: MiniJobs.Plugs.Logger
     ↓
Endpoint Handler (MiniJobs.API.JobsController)
     ↓
Business Logic → Queue Processing
     ↓
Plug 4: MiniJobs.Plugs.ResponseFormatter
     ↓
Cowboy Response generation
     ↓
HTTP Response sent
```

## Development Phases

### Phase 1: Core Infrastructure (Week 1)

#### 1.1 HTTP Server Setup
- **Tasks:**
  - Initialize Cowboy HTTP server
  - Create basic router configuration
  - Implement JSON request/response handling
  - Add basic error middleware

- **Files to modify/create:**
  - `lib/mini_jobs/application.ex` (add Cowboy to supervisor tree)
  - `lib/mini_jobs/cowboy_handler.ex` ( Cowboy HTTP handler)
  - `lib/mini_jobs/router.ex` (custom Plug router)
  - `lib/mini_jobs/plugs/json_parser.ex` (JSON body parsing)
  - `lib/mini_jobs/plugs/request_validator.ex` (request validation)
  - `lib/mini_jobs/plugs/logger.ex` (request logging)
  - `lib/mini_jobs/plugs/response_formatter.ex` (response formatting)
  - `lib/mini_jobs/api/jobs_controller.ex` (job API handlers)
  - `config/config.exs` (Cowboy and Plug configuration)

- **Expected outcomes:**
  - HTTP server running on port 4000
  - Basic health check endpoint
  - JSON request/response handling

#### 1.2 Basic Job API
- **Tasks:**
  - Implement POST /api/jobs endpoint using custom Plug router
  - Manual job request validation (no schema libraries)
  - Basic job structure definition with maps
  - Simple success/failure responses with custom JSON formatting

- **API specification:**
  ```json
  POST /api/jobs
  Request: {"command": "echo 'hello'", "priority": "normal"}
  Response: {"job_id": "uuid", "status": "queued"}
  ```

### Phase 2: Job Processing Engine (Week 2)

#### 2.1 Queue Manager Implementation
- **Tasks:**
  - Create ETS-based job queue
  - Implement FIFO ordering
  - Add job priority support
  - Queue persistence mechanisms

- **Components:**
  - `lib/mini_jobs/queue_manager.ex`
  - `lib/mini_jobs/job_registry.ex`
  - Job state management (pending, running, completed, failed)

#### 2.2 Enhanced Worker System
- **Tasks:**
  - Dynamic worker supervision
  - Worker pool scaling
  - Job distribution logic
  - Timeout and retry mechanisms

- **Components:**
  - `lib/mini_jobs/worker_supervisor.ex`
  - `lib/mini_jobs/job_worker.ex` (enhanced version)
  - Worker health monitoring

#### 2.3 Job Status Tracking
- **Tasks:**
  - Implement GET /api/jobs/:id endpoint
  - Job status real-time updates
  - Result retrieval and storage
  - Job history tracking

### Phase 3: Advanced Features (Week 3)

#### 3.1 Enhanced API Endpoints
- **Tasks:**
  - Implement GET /api/jobs (list all jobs)
  - Add DELETE /api/jobs/:id (job cancellation)
  - Add PUT /api/jobs/:id (job rescheduling)
  - Bulk operations support

- **API endpoints:**
  - `GET /api/jobs?status=pending&limit=50`
  - `DELETE /api/jobs/:id` (cancel running job)
  - `PUT /api/jobs/:id/pause` (pause/resume)

#### 3.2 Error Handling & Recovery
- **Tasks:**
  - Comprehensive error handling
  - Dead letter queue implementation
  - Retry mechanisms with exponential backoff
  - Job cleanup and resource management

- **Components:**
  - `lib/mini_jobs/dead_letter_queue.ex`
  - `lib/mini_jobs/retry_handler.ex`
  - Error logging and reporting

#### 3.3 Performance Optimization
- **Tasks:**
  - Worker pool auto-scaling
  - Connection pooling optimization
  - Memory usage optimization
  - Concurrent processing improvements

### Phase 4: Monitoring & Observability (Week 4)

#### 4.1 Monitoring System
- **Tasks:**
  - Job metrics collection
  - Performance monitoring
  - System health checks
  - Alert mechanisms

- **Components:**
  - `lib/mini_jobs/metrics.ex`
  - Health check endpoints
  - Performance dashboard

#### 4.2 Documentation & Testing
- **Tasks:**
  - API documentation generation
  - Comprehensive test suite
  - Load testing implementation
  - Code coverage analysis

## Technical Specifications

### Data Models

#### Job Structure
```elixir
%{
  id: UUID,
  command: String,
  priority: :high | :normal | :low,
  status: :pending | :running | :completed | :failed | :cancelled,
  created_at: DateTime,
  started_at: DateTime | nil,
  completed_at: DateTime | nil,
  result: term() | nil,
  error: String | nil,
  timeout: Integer() # milliseconds,
  retry_count: Integer(),
  max_retries: Integer()
}
```

#### API Requests

##### Submit Job
```json
POST /api/jobs
{
  "command": "string",
  "priority": "normal",
  "timeout": 30000,
  "max_retries": 3
}
```

##### List Jobs
```json
GET /api/jobs?status=pending&limit=50&offset=0
Response:
{
  "jobs": [
    {"id": "uuid", "status": "pending", "created_at": "timestamp"}
  ],
  "total": 100
}
```

##### Get Job Status
```json
GET /api/jobs/uuid
Response:
{
  "id": "uuid",
  "status": "running",
  "created_at": "timestamp",
  "started_at": "timestamp",
  "progress": 45
}
```

### Configuration

#### Application Configuration
```elixir
# config/config.exs
config :mini_jobs,
  http_port: 4000,
  cowboy_opts: [
    {:port, 4000},
    {:num_acceptors, 100},
    {:max_connections, 16384},
    {:idle_timeout, 60000}
  ],
  max_workers: 10,
  job_timeout: 30000,
  max_retries: 3,
  queue_size: 1000

# Plug pipeline configuration
config :mini_jobs, :plug_pipeline,
  plugs: [
    MiniJobs.Plugs.Logger,
    MiniJobs.Plugs.JSONParser,
    MiniJobs.Plugs.RequestValidator
  ]
```

## Success Metrics

### Performance Targets
- 1000+ jobs per second throughput
- < 10ms job submission latency
- 99.9% job success rate
- Auto-scaling in < 1 second

### Quality Targets
- 95%+ code coverage
- < 1ms average response time for API calls
- Zero data loss tolerance
- Zero memory leaks after 24-hour operation

## Risk Assessment

### Technical Risks
- **Concurrency challenges**: Complex state management with multiple workers
- **Memory usage**: Potential memory leaks with long-running jobs
- **Timeout handling**: Job cleanup and resource management
- **Scalability**: Performance bottlenecks under high load

### Mitigation Strategies
- **Comprehensive testing**: Property-based testing for concurrent scenarios
- **Memory monitoring**: Regular memory profiling and garbage collection
- **Load testing**: Simulate production scenarios before deployment
- **Circuit breakers**: Prevent cascade failures

## Timeline and Milestones

### Week 1: Foundation ✅ COMPLETED
- [x] Project structure and dependencies
- [x] Basic HTTP server with Cowboy
- [x] Simple job submission API
- [x] Health check endpoint
- [x] JSON request/response handling
- [x] Custom Plug router implementation

### Week 2: Processing Core ✅ COMPLETED
- [x] Queue manager implementation with ETS tables
- [x] Dynamic worker supervisor
- [x] Job status tracking system
- [x] Complete error handling and logging
- [x] Job retry mechanism with backoff
- [x] Worker auto-scaling

### Week 3: Advanced Features ✅ COMPLETED
- [x] Complete API set (GET/POST/DELETE)
- [x] Job filtering and pagination
- [x] Priority-based queue processing
- [x] Performance optimizations
- [x] Comprehensive error recovery
- [x] Request parameter handling

### Week 4: Production Readiness ⚠️ MOSTLY DONE
- [x] Monitoring and structured logging
- [x] Basic documentation
- [ ] Load testing
- [x] Configuration system

## Dependencies

### Elixir/Erlang Libraries
- **Cowboy**: NIF-based HTTP server for high performance
- **Plug**: Minimal connection adapter (no Phoenix framework)
- **UUID**: Job ID generation (ex UUID)
- **Jason**: Fast JSON encoder/decoder
- **Logger**: Structured logging (built-in Elixir)
- **Telemetry**: Metrics collection (for monitoring)

### Plug Pipeline Components
- **JSON Parser**: Custom Plug for request body parsing
- **Request Validator**: Custom Plug for validation
- **Logger Plug**: Request/response logging
- **Response Formatter**: Custom Plug for consistent responses
- **Error Handler**: Custom Plug for error formatting

### System Requirements
- **Minimum**: 1 CPU core, 1GB RAM
- **Recommended**: 4 CPU cores, 4GB RAM
- **Production**: 8+ CPU cores, 16GB+ RAM

## Future Enhancements

### Phase 5 (Post-Launch)
- **Web Dashboard**: React/Vue.js frontend for monitoring
- **Job Templates**: Pre-defined job workflows
- **Scheduling**: Cron-like scheduling capabilities
- **Distributed Processing**: Multi-node cluster support
- **Database Persistence**: PostgreSQL/MySQL integration
- **Authentication**: JWT-based API authentication (custom Plug)
- **Rate Limiting**: Plug-based rate limiting
- **Request Compression**: Plug for response compression
- **CORS Support**: Custom CORS Plug configuration

### Phase 6 (Advanced)
- **Real-time Updates**: WebSocket notifications using Cowboy Websockets
- **Plugin System**: Custom job types and processors with Plug hooks
- **Metrics Analytics**: Advanced reporting with Telemetry
- **Auto-scaling**: Dynamic worker pool with Load Shedding Plug
- **API Documentation**: Plug-based OpenAPI/Swagger documentation
- **Request Body Encryption**: Plug for sensitive data handling
- **Circuit Breakers**: Plug-based fault tolerance