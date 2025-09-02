# Error Handling Improvement Plan

## Implementation Roadmap

This document outlines the step-by-step plan to implement robust error handling in the mini-jobs application.

### Phase 1: Critical Infrastructure (Week 1)

#### 1.1 Implement Plug.ErrorHandler
**Goal**: Add proper error handling for uncaught exceptions in the router

**Technical Details**:
- **Plug.ErrorHandler** is a behavior that intercepts all uncaught exceptions in the plug pipeline
- It requires implementing the `handle_errors/2` callback which receives:
  - `conn`: The connection (with status already set)
  - `%{kind: kind, reason: reason, stack: stack}`: Error metadata
- **Order is critical**: Plug.Debugger must be used before Plug.ErrorHandler and only in development
- **Important**: Do not access params/session in error handler as they may have caused the error

**Tasks**:
1. **Add Plug.ErrorHandler to router**
   - Add `use Plug.ErrorHandler` to `MiniJobs.Router`
   - Ensure proper plug ordering: Plug.Debugger (dev only) → Logger → Parsers → Other plugs → match → dispatch
   - Handle the case where connection has already been sent

2. **Implement `handle_errors/2` callback**
   - Create structured error response format
   - Handle different error kinds: `:error`, `:throw`, `:exit`
   - For HTTP errors, use `conn.status` (400, 404, 500, etc.)
   - Format response as JSON with consistent structure

3. **Add conditional `Plug.Debugger`**
   - Add only in development environment with `if Mix.env() == :dev`
   - Configure with `use Plug.Debugger, otp_app: :mini_jobs`
   - Verify it renders detailed error pages with stack traces
   - Ensure it links to source code if PLUG_EDITOR is set

4. **Test error scenarios**
   - Test with invalid JSON in request body
   - Test with route that raises an exception
   - Test with missing headers
   - Test with 404 handling
   - Verify error responses are JSON, not HTML

**Implementation Details**:
```elixir
# router.ex
defmodule MiniJobs.Router do
  use Plug.Router
  use Plug.ErrorHandler

  if Mix.env() == :dev do
    use Plug.Debugger, otp_app: :mini_jobs
  end

  # ... other plugs

  @impl Plug.ErrorHandler
  def handle_errors(conn, %{kind: kind, reason: reason, stack: stack}) do
    # Extract error details
    error_details = %{
      kind: kind,
      reason: reason,
      stack: stack
    }

    # Check if response already sent
    case get_resp_header(conn, "connection") do
      ["close"] -> conn
      _ -> send_error_response(conn, conn.status, error_details)
    end
  end

  defp send_error_response(conn, status, error_details) do
    # Implementation to create JSON error response
  end
end
```

**Files to modify**:
- `router.ex`
- Add new `error_helpers.ex` module for shared error formatting
- Create `MiniJobs.Error` module for error types

**Acceptance Criteria**:
- All uncaught exceptions return proper JSON error responses
- Development environment shows detailed error information with source links
- Production environment shows generic error messages (no stack traces)
- 404 errors have consistent format with path and method info
- Error responses include request ID for tracking
- No crashes from error handling itself

#### 1.2 Fix JSON Encoding Issues
**Goal**: Prevent crashes from JSON encoding failures

**Technical Details**:
- **Current Issue**: Using `Jason.encode!/1` without try/catch will crash the entire request if encoding fails
- **Common Causes**: 
  - Circular references in data structures
  - Non-encodable terms (pids, ports, references)
  - Strings with invalid UTF-8 sequences
  - Terms larger than 1MB (Jason's default limit)
- **Impact**: A single encoding failure can crash the entire web request, potentially affecting multiple users

**Tasks**:
1. **Replace all `Jason.encode!/1` calls**
   - Identify all locations using `Jason.encode!/1`:
     - `router.ex:48` (json helper)
     - `jobs_controller.ex:138, 152` (json and send_error helpers)
     - `request_validator.ex:32` (send_error_response)
     - `error_controller.ex:18` (json helper)
     - `plugs/logger.ex` (if JSON is used for structured logs)
   - Replace with safe wrapper function

2. **Create centralized JSON encoding helper**
   - Implement `MiniJobs.Json.encode/1` that handles encoding errors
   - Add logging for encoding failures (with request ID if available)
   - Implement fallback behavior for different error types
   - Consider using `Jason.encode/1` instead of `!/1` for better error handling

3. **Handle specific error cases**
   - For circular references: implement depth limiting or convert to string representation
   - For non-encodable terms: convert to string using `inspect/1` or filter out
   - For large terms: implement size limiting and truncation
   - For invalid UTF-8: detect and handle gracefully

4. **Add response size limiting**
   - Consider implementing maximum response size limits
   - Compress large responses if needed
   - Log responses that exceed size limits

**Implementation Details**:
```elixir
# lib/mini_jobs/json.ex
defmodule MiniJobs.Json do
  @moduledoc """
  Safe JSON encoding with fallback for error cases.
  """

  @max_response_size 10 * 1024 * 1024  # 10MB
  @max_encoding_depth 100

  def encode(data) when is_map(data) do
    try do
      # Try with depth limit to catch circular references
      Jason.encode!(data, escape: :native, strings: :copy)
    rescue
      ArgumentError ->
        Logger.warning("JSON encoding failed for map, trying with sanitization")
        sanitize_and_encode(data)
      
      error ->
        Logger.error("JSON encoding error: #{inspect(error)}")
        fallback_error_response()
    end
  end

  def encode(data) do
    try do
      Jason.encode!(data, escape: :native, strings: :copy)
    rescue
      ArgumentError ->
        Logger.warning("JSON encoding failed for data: #{inspect(data)}")
        fallback_error_response()
    end
  end

  defp sanitize_and_encode(data, depth \\ 0) when depth < @max_encoding_depth do
    # Sanitize data by removing non-encodable terms
    sanitized = sanitize_data(data)
    Jason.encode!(sanitized)
  rescue
    ArgumentError ->
      # If still failing, convert to string
      Jason.encode!(%{"error" => "Data too complex to encode"})
  end

  defp sanitize_data(data) when is_map(data) do
    data
    |> Enum.map(fn {k, v} -> {k, sanitize_data(v)} end)
    |> Map.new()
  end

  defp sanitize_data(data) when is_list(data) do
    Enum.map(data, &sanitize_data/1)
  end

  defp sanitize_data(data) when is_pid(data) or is_reference(data) or is_port(data) do
    inspect(data)
  end

  defp sanitize_data(data), do: data

  defp fallback_error_response do
    Jason.encode!(%{
      "error" => "Internal Server Error",
      "message" => "Failed to encode response"
    })
  end
end
```

**Files to modify**:
- `router.ex` - Replace Jason.encode!/1 calls in json helper
- `jobs_controller.ex` - Replace Jason.encode!/1 calls in json and send_error helpers
- `request_validator.ex` - Replace in send_error_response
- `error_controller.ex` - Replace in json helper
- `plugs/logger.ex` - If using JSON for structured logs

**Files to create**:
- `lib/mini_jobs/json.ex` - Safe JSON encoding module

**Acceptance Criteria**:
- No crashes from JSON encoding failures
- Invalid data sanitized and returned with appropriate error
- All JSON responses use the centralized encoding function
- Performance impact minimal (<1% overhead)
- Fallback responses include error ID for tracking

#### 1.3 Create Centralized Error Response Module
**Goal**: Standardize all error responses across the application

**Tasks**:
1. Create `MiniJobs.Errors` module
2. Define error response structure
3. Create error types and codes
4. Add helper functions for common errors

**Files to create**:
- `errors.ex`
- `error_helpers.ex`

**Acceptance Criteria**:
- All error responses follow the same format
- Error codes match HTTP status codes
- Include request ID for tracking
- Timestamp for all responses

### Phase 2: Request and Response Handling (Week 2)

#### 2.1 Improve Request Validation
**Goal**: Comprehensive input validation with proper error responses

**Tasks**:
1. Create validation schema for job creation
2. Add parameter validation for all endpoints
3. Validate query parameters (limit, offset)
4. Handle validation errors consistently

**Files to modify**:
- `request_validator.ex`
- `jobs_controller.ex`
- Add new `job_validation.ex` module

**Acceptance Criteria**:
- Invalid requests return 400 with detailed error messages
- Validation errors follow standard error format
- Clear error messages for each validation failure
- Efficient validation without performance impact

#### 2.2 Add Error Boundaries to Plugs
**Goal**: Ensure errors in plugs don't affect the entire request pipeline

**Tasks**:
1. Wrap all plug functions in try/catch
2. Return appropriate error responses
3. Log errors with context
4. Test plug error scenarios

**Files to modify**:
- `plugs/request_validator.ex`
- `plugs/logger.ex`
- Add new `plugs/error_boundary.ex`

**Acceptance Criteria**:
- Plug errors don't crash the request
- Proper error responses returned to client
- Errors are logged with sufficient context
- Performance not significantly impacted

#### 2.3 Enhance GenServer Error Handling
**Goal**: Robust error handling in all GenServer processes

**Tasks**:
1. Add error handling in queue_manager.ex ETS operations
2. Handle errors when starting QueueManager/WorkerSupervisor
3. Add proper state recovery
4. Implement circuit breaker pattern for workers

**Files to modify**:
- `queue_manager.ex`
- `job_processor.ex`
- `job_worker.ex`
- `worker_supervisor.ex`

**Acceptance Criteria**:
- GenServers handle all error scenarios gracefully
- Failed operations don't leave inconsistent state
- Automatic recovery from transient failures
- Proper logging of error details

### Phase 3: Job Processing Improvements (Week 3)

#### 3.1 Fix Job Lifecycle Error Handling
**Goal**: Ensure jobs complete successfully or fail consistently

**Tasks**:
1. Add transaction-like behavior for job status updates
2. Handle failures when updating job status
3. Retry failed status updates
4. Add job consistency checks

**Files to modify**:
- `job_worker.ex`
- `queue_manager.ex`
- Add new `job_consistency.ex` module

**Acceptance Criteria**:
- Jobs always end up in a final state (completed/failed/cancelled)
- Status update failures are recovered automatically
- No orphaned jobs
- Recovery process runs periodically

#### 3.2 Improve Job Worker Error Recovery
**Goal**: Better error handling and recovery in job workers

**Tasks**:
1. Separate timeout handling from execution errors
2. Add more specific error categories
3. Implement exponential backoff for retries
4. Add worker health checks

**Files to modify**:
- `job_worker.ex`
- Add new `job_retry_strategy.ex` module

**Acceptance Criteria**:
- Different error types handled differently
- Retry delays increase with each attempt
- Workers recover from temporary failures
- Maximum retry limits enforced properly

### Phase 4: Monitoring and Observability (Week 4)

#### 4.1 Add Structured Logging
**Goal**: Log errors with proper context for debugging

**Tasks**:
1. Add request IDs to all logs
2. Include error context in log messages
3. Use structured logging format
4. Add performance metrics for errors

**Files to modify**:
- `plugs/logger.ex`
- All controller files
- GenServer modules
- Add new `logging.ex` module

**Acceptance Criteria**:
- Every request has a unique ID
- Error context included in log messages
- Log format is consistent and parseable
- Error rates tracked by type

#### 4.2 Implement Error Tracking
**Goal**: Track and report errors for monitoring

**Tasks**:
1. Add error tracking with unique IDs
2. Integrate with error reporting service
3. Track error rates and patterns
4. Set up alerts for critical errors

**Files to create**:
- `error_tracking.ex`
- `error_reporter.ex`

**Acceptance Criteria**:
- Each error has a unique tracking ID
- Errors are reported to external service
- Error dashboard shows key metrics
- Alerts configured for critical errors

#### 4.3 Add Telemetry for Errors
**Goal**: Monitor error events for observability

**Tasks**:
1. Add telemetry events for error scenarios
2. Measure error rates and durations
3. Track error distribution by type
4. Create dashboards for error monitoring

**Files to modify**:
- Add telemetry to all modules
- Create telemetry setup module

**Acceptance Criteria**:
- Error telemetry events emitted consistently
- Metrics collection working
- Dashboards show error trends
- Performance impact minimal

### Phase 5: Testing and Quality Assurance (Week 5)

#### 5.1 Comprehensive Error Testing
**Goal**: Ensure all error scenarios are covered by tests

**Tasks**:
1. Write unit tests for error handling
2. Integration tests for error scenarios
3. Property-based testing for edge cases
4. Performance testing under error conditions

**Files to create**:
- `test/errors_test.exs`
- Test helpers for error scenarios

**Acceptance Criteria**:
- >90% test coverage for error handling code
- All error paths tested
- Error recovery verified
- Performance benchmarks met

#### 5.2 Error Scenarios Documentation
**Goal**: Document all error scenarios and their handling

**Tasks**:
1. Create error handling matrix
2. Document error recovery procedures
3. Create troubleshooting guide
4. Add error codes documentation

**Files to create**:
- `docs/error-scenarios.md`
- `docs/error-codes.md`

**Acceptance Criteria**:
- All error scenarios documented
- Recovery procedures clear and actionable
- Troubleshooting guide comprehensive
- Documentation accessible to team

## Implementation Strategy

### Technical Approach
1. **Start small**: Begin with the most critical issues
2. **Test-driven**: Write tests before implementing fixes
3. **Incremental**: Deploy changes in small batches
4. **Monitor closely**: Watch error rates during deployment

### Team Structure
- **Lead Developer**: Overall architecture and implementation
- **Backend Developer**: Server-side error handling implementation
- **QA Engineer**: Testing and validation
- **DevOps**: Deployment monitoring and alerts

### Timeline
- **Phase 1**: 1 week
- **Phase 2**: 1 week
- **Phase 3**: 1 week
- **Phase 4**: 1 week
- **Phase 5**: 1 week
- **Total**: 5 weeks

### Risk Mitigation
1. **Rollback strategy**: Each phase can be rolled back independently
2. **Feature flags**: Enable new error handling behind flags
3. **Canary deployment**: Gradual rollout to production
4. **Monitoring alerts**: Immediate notification if error rates increase

### Success Metrics
1. **Zero uncaught exceptions** in production
2. **Error response consistency** 100%
3. **Error recovery time** < 5 seconds
4. **Test coverage** > 90%
5. **Error alerting** 100% effective

## Conclusion

This comprehensive error handling improvement plan will transform the mini-jobs application from having basic error handling to having robust, production-ready error handling. The implementation follows best practices and will significantly improve the reliability and maintainability of the application.

The phased approach ensures that critical issues are addressed first while allowing for gradual improvement and validation of each change. The plan includes proper testing, monitoring, and documentation to ensure long-term success.