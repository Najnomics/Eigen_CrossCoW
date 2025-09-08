package operator

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/Layr-Labs/eigensdk-go/logging"
	"github.com/ethereum/go-ethereum/common"
)

// TaskProcessor handles the processing of matching tasks with sophisticated scheduling and batching
type TaskProcessor struct {
	config                Config
	logger                logging.Logger
	
	// Task queues and management
	pendingTasks          chan *MatchingTask
	priorityTasks         chan *MatchingTask
	processingTasks       map[uint32]*MatchingTask
	completedTasks        map[uint32]*TaskResult
	
	// Synchronization and state management
	mutex                 sync.RWMutex
	isRunning            bool
	workerPool           []*TaskWorker
	batchProcessor       *BatchProcessor
	
	// Performance tracking
	stats                *ProcessorStats
	healthChecker        *HealthChecker
}

// TaskResult represents the result of processing a task
type TaskResult struct {
	TaskIndex       uint32      `json:"taskIndex"`
	Success         bool        `json:"success"`
	Error           string      `json:"error"`
	ProcessingTime  time.Duration `json:"processingTime"`
	RetryCount      int         `json:"retryCount"`
	CompletedAt     time.Time   `json:"completedAt"`
	AcrossDepositId common.Hash `json:"acrossDepositId"`
	GasUsed         uint64      `json:"gasUsed"`
}

// TaskWorker represents a worker that processes individual tasks
type TaskWorker struct {
	id            int
	processor     *TaskProcessor
	taskChan      chan *MatchingTask
	logger        logging.Logger
	isActive      bool
	lastActivity  time.Time
	processedCount int64
}

// BatchProcessor handles batching of similar tasks for efficiency
type BatchProcessor struct {
	logger          logging.Logger
	batchSize       int
	batchTimeout    time.Duration
	pendingBatches  map[string][]*MatchingTask // chainPair -> tasks
	mutex           sync.RWMutex
}

// ProcessorStats tracks performance metrics
type ProcessorStats struct {
	TasksReceived     int64     `json:"tasksReceived"`
	TasksProcessed    int64     `json:"tasksProcessed"`
	TasksSuccessful   int64     `json:"tasksSuccessful"`
	TasksFailed       int64     `json:"tasksFailed"`
	AverageTime       time.Duration `json:"averageProcessingTime"`
	ThroughputPerMin  float64   `json:"throughputPerMinute"`
	LastUpdated       time.Time `json:"lastUpdated"`
}

// HealthChecker monitors the health of the task processor
type HealthChecker struct {
	logger            logging.Logger
	lastHealthCheck   time.Time
	consecutiveErrors int
	maxErrorThreshold int
	isHealthy         bool
}

// NewTaskProcessor creates a new task processor with configured workers
func NewTaskProcessor(config Config, logger logging.Logger) *TaskProcessor {
	logger = logger.With("component", "task-processor")
	
	tp := &TaskProcessor{
		config:          config,
		logger:          logger,
		pendingTasks:    make(chan *MatchingTask, 1000),
		priorityTasks:   make(chan *MatchingTask, 100),
		processingTasks: make(map[uint32]*MatchingTask),
		completedTasks:  make(map[uint32]*TaskResult),
		stats:           &ProcessorStats{LastUpdated: time.Now()},
		healthChecker:   &HealthChecker{
			logger:            logger.With("component", "health-checker"),
			maxErrorThreshold: 5,
			isHealthy:         true,
		},
	}
	
	// Initialize batch processor
	tp.batchProcessor = &BatchProcessor{
		logger:         logger.With("component", "batch-processor"),
		batchSize:      10,
		batchTimeout:   30 * time.Second,
		pendingBatches: make(map[string][]*MatchingTask),
	}
	
	// Initialize worker pool
	maxWorkers := config.MaxConcurrentTasks
	if maxWorkers <= 0 {
		maxWorkers = 5 // Default to 5 workers
	}
	
	tp.workerPool = make([]*TaskWorker, maxWorkers)
	for i := 0; i < maxWorkers; i++ {
		tp.workerPool[i] = &TaskWorker{
			id:           i,
			processor:    tp,
			taskChan:     make(chan *MatchingTask, 10),
			logger:       logger.With("worker", i),
			lastActivity: time.Now(),
		}
	}
	
	tp.logger.Info("Task processor initialized",
		"maxWorkers", maxWorkers,
		"batchSize", tp.batchProcessor.batchSize,
	)
	
	return tp
}

// Start begins the task processing with all workers and monitoring
func (tp *TaskProcessor) Start(ctx context.Context) error {
	tp.mutex.Lock()
	if tp.isRunning {
		tp.mutex.Unlock()
		return fmt.Errorf("task processor already running")
	}
	tp.isRunning = true
	tp.mutex.Unlock()
	
	tp.logger.Info("Starting task processor with workers", "workerCount", len(tp.workerPool))
	
	// Start all workers
	for _, worker := range tp.workerPool {
		go worker.start(ctx)
	}
	
	// Start task dispatcher
	go tp.dispatchTasks(ctx)
	
	// Start batch processor
	go tp.batchProcessor.start(ctx)
	
	// Start health monitoring
	go tp.healthChecker.start(ctx, tp)
	
	// Start metrics collector
	go tp.collectStats(ctx)
	
	tp.logger.Info("Task processor started successfully")
	return nil
}

// Stop gracefully shuts down the task processor
func (tp *TaskProcessor) Stop(ctx context.Context) error {
	tp.mutex.Lock()
	defer tp.mutex.Unlock()
	
	if !tp.isRunning {
		return fmt.Errorf("task processor not running")
	}
	
	tp.logger.Info("Stopping task processor")
	tp.isRunning = false
	
	// Close channels to signal shutdown
	close(tp.pendingTasks)
	close(tp.priorityTasks)
	
	// Wait for workers to finish current tasks
	for _, worker := range tp.workerPool {
		worker.shutdown()
	}
	
	tp.logger.Info("Task processor stopped")
	return nil
}

// SubmitTask adds a new task to the processing queue
func (tp *TaskProcessor) SubmitTask(task *MatchingTask) error {
	if !tp.isRunning {
		return fmt.Errorf("task processor not running")
	}
	
	tp.stats.TasksReceived++
	
	// Determine if this is a priority task based on deadline urgency
	deadline := time.Unix(int64(task.Deadline), 0)
	urgency := time.Until(deadline)
	
	tp.logger.Debug("Submitting task",
		"taskIndex", task.TaskIndex,
		"deadline", deadline,
		"urgency", urgency,
	)
	
	// Priority tasks are those with less than 5 minutes to deadline
	if urgency < 5*time.Minute {
		select {
		case tp.priorityTasks <- task:
			tp.logger.Info("Task queued as priority", "taskIndex", task.TaskIndex)
			return nil
		default:
			// Priority queue full, fall back to normal queue
			tp.logger.Warn("Priority queue full, using normal queue", "taskIndex", task.TaskIndex)
		}
	}
	
	select {
	case tp.pendingTasks <- task:
		tp.logger.Debug("Task queued for processing", "taskIndex", task.TaskIndex)
		return nil
	default:
		return fmt.Errorf("task queue full")
	}
}

// dispatchTasks distributes tasks from queues to available workers
func (tp *TaskProcessor) dispatchTasks(ctx context.Context) {
	tp.logger.Info("Task dispatcher started")
	
	for {
		select {
		case <-ctx.Done():
			tp.logger.Info("Task dispatcher shutting down")
			return
			
		// Priority tasks get precedence
		case task := <-tp.priorityTasks:
			if task == nil { // Channel closed
				return
			}
			tp.assignTaskToWorker(task)
			
		// Regular tasks
		case task := <-tp.pendingTasks:
			if task == nil { // Channel closed
				return
			}
			
			// Check if we can batch this task
			if tp.shouldBatchTask(task) {
				tp.batchProcessor.addToBatch(task)
			} else {
				tp.assignTaskToWorker(task)
			}
		}
	}
}

// assignTaskToWorker finds an available worker and assigns the task
func (tp *TaskProcessor) assignTaskToWorker(task *MatchingTask) {
	// Find the least busy worker
	var selectedWorker *TaskWorker
	minLoad := int64(1000000) // Large number
	
	for _, worker := range tp.workerPool {
		if worker.isActive && worker.processedCount < minLoad {
			selectedWorker = worker
			minLoad = worker.processedCount
		}
	}
	
	if selectedWorker == nil {
		// All workers busy, try to queue with the first available
		for _, worker := range tp.workerPool {
			select {
			case worker.taskChan <- task:
				tp.logger.Debug("Task assigned to worker", 
					"taskIndex", task.TaskIndex, 
					"worker", worker.id,
				)
				return
			default:
				continue
			}
		}
		
		// All workers are full, log warning and try again later
		tp.logger.Warn("All workers busy, task will retry", "taskIndex", task.TaskIndex)
		go func() {
			time.Sleep(1 * time.Second)
			tp.assignTaskToWorker(task)
		}()
		return
	}
	
	select {
	case selectedWorker.taskChan <- task:
		tp.logger.Debug("Task assigned to worker", 
			"taskIndex", task.TaskIndex, 
			"worker", selectedWorker.id,
		)
	default:
		tp.logger.Warn("Worker queue full, task will retry", 
			"taskIndex", task.TaskIndex, 
			"worker", selectedWorker.id,
		)
	}
}

// shouldBatchTask determines if a task can be batched with similar tasks
func (tp *TaskProcessor) shouldBatchTask(task *MatchingTask) bool {
	// Tasks can be batched if they're on the same chain pair and within time window
	chainPair := fmt.Sprintf("%d-%d", task.Trade.ChainA, task.Trade.ChainB)
	
	tp.batchProcessor.mutex.RLock()
	defer tp.batchProcessor.mutex.RUnlock()
	
	if batch, exists := tp.batchProcessor.pendingBatches[chainPair]; exists {
		return len(batch) < tp.batchProcessor.batchSize
	}
	
	return true // Can start a new batch
}

// GetTaskResult retrieves the result of a completed task
func (tp *TaskProcessor) GetTaskResult(taskIndex uint32) (*TaskResult, bool) {
	tp.mutex.RLock()
	defer tp.mutex.RUnlock()
	
	result, exists := tp.completedTasks[taskIndex]
	return result, exists
}

// GetStats returns current processor statistics
func (tp *TaskProcessor) GetStats() *ProcessorStats {
	tp.mutex.RLock()
	defer tp.mutex.RUnlock()
	
	stats := *tp.stats
	stats.LastUpdated = time.Now()
	
	// Calculate throughput
	if tp.stats.TasksProcessed > 0 {
		duration := time.Since(tp.stats.LastUpdated).Minutes()
		if duration > 0 {
			stats.ThroughputPerMin = float64(tp.stats.TasksProcessed) / duration
		}
	}
	
	return &stats
}

// collectStats periodically updates processor statistics
func (tp *TaskProcessor) collectStats(ctx context.Context) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			tp.updateStats()
		}
	}
}

// updateStats recalculates processor statistics
func (tp *TaskProcessor) updateStats() {
	tp.mutex.Lock()
	defer tp.mutex.Unlock()
	
	// Calculate average processing time
	if tp.stats.TasksProcessed > 0 {
		totalTime := time.Duration(0)
		count := 0
		
		for _, result := range tp.completedTasks {
			totalTime += result.ProcessingTime
			count++
		}
		
		if count > 0 {
			tp.stats.AverageTime = totalTime / time.Duration(count)
		}
	}
	
	tp.stats.LastUpdated = time.Now()
	
	tp.logger.Debug("Stats updated",
		"processed", tp.stats.TasksProcessed,
		"successful", tp.stats.TasksSuccessful,
		"failed", tp.stats.TasksFailed,
		"avgTime", tp.stats.AverageTime,
	)
}

// TaskWorker methods

// start begins the worker's task processing loop
func (tw *TaskWorker) start(ctx context.Context) {
	tw.isActive = true
	tw.logger.Info("Task worker started")
	
	defer func() {
		tw.isActive = false
		tw.logger.Info("Task worker stopped")
	}()
	
	for {
		select {
		case <-ctx.Done():
			return
		case task := <-tw.taskChan:
			if task == nil { // Channel closed
				return
			}
			tw.processTask(task)
		}
	}
}

// processTask handles the execution of a single task
func (tw *TaskWorker) processTask(task *MatchingTask) {
	startTime := time.Now()
	tw.lastActivity = startTime
	tw.processedCount++
	
	tw.logger.Info("Processing task", 
		"taskIndex", task.TaskIndex,
		"worker", tw.id,
	)
	
	// Mark task as being processed
	tw.processor.mutex.Lock()
	tw.processor.processingTasks[task.TaskIndex] = task
	tw.processor.mutex.Unlock()
	
	// Create task result
	result := &TaskResult{
		TaskIndex:  task.TaskIndex,
		CompletedAt: time.Now(),
	}
	
	// Simulate task processing (in real implementation, this would call actual processing logic)
	success, acrossDepositId, gasUsed := tw.executeTaskLogic(task)
	
	processingTime := time.Since(startTime)
	result.ProcessingTime = processingTime
	result.Success = success
	result.AcrossDepositId = acrossDepositId
	result.GasUsed = gasUsed
	
	if !success {
		result.Error = "Task execution failed"
	}
	
	// Store result
	tw.processor.mutex.Lock()
	tw.processor.completedTasks[task.TaskIndex] = result
	delete(tw.processor.processingTasks, task.TaskIndex)
	
	// Update stats
	tw.processor.stats.TasksProcessed++
	if success {
		tw.processor.stats.TasksSuccessful++
	} else {
		tw.processor.stats.TasksFailed++
	}
	tw.processor.mutex.Unlock()
	
	tw.logger.Info("Task completed",
		"taskIndex", task.TaskIndex,
		"success", success,
		"processingTime", processingTime,
		"worker", tw.id,
	)
}

// executeTaskLogic performs the actual task execution logic
func (tw *TaskWorker) executeTaskLogic(task *MatchingTask) (bool, common.Hash, uint64) {
	// In a real implementation, this would:
	// 1. Validate the task parameters
	// 2. Execute the cross-chain trade via Across Protocol
	// 3. Monitor the execution
	// 4. Return the results
	
	// For now, simulate success/failure
	success := true
	acrossDepositId := common.BytesToHash([]byte(fmt.Sprintf("deposit_%d", task.TaskIndex)))
	gasUsed := uint64(21000 + (task.TaskIndex % 50000)) // Simulate variable gas usage
	
	// Simulate some processing time
	time.Sleep(100 * time.Millisecond)
	
	return success, acrossDepositId, gasUsed
}

// shutdown gracefully stops the worker
func (tw *TaskWorker) shutdown() {
	tw.isActive = false
	close(tw.taskChan)
}

// BatchProcessor methods

// start begins the batch processing loop
func (bp *BatchProcessor) start(ctx context.Context) {
	ticker := time.NewTicker(bp.batchTimeout)
	defer ticker.Stop()
	
	for {
		select {
		case <-ctx.Done():
			bp.processPendingBatches()
			return
		case <-ticker.C:
			bp.processPendingBatches()
		}
	}
}

// addToBatch adds a task to the appropriate batch
func (bp *BatchProcessor) addToBatch(task *MatchingTask) {
	chainPair := fmt.Sprintf("%d-%d", task.Trade.ChainA, task.Trade.ChainB)
	
	bp.mutex.Lock()
	defer bp.mutex.Unlock()
	
	if _, exists := bp.pendingBatches[chainPair]; !exists {
		bp.pendingBatches[chainPair] = make([]*MatchingTask, 0, bp.batchSize)
	}
	
	bp.pendingBatches[chainPair] = append(bp.pendingBatches[chainPair], task)
	
	// Process batch if it's full
	if len(bp.pendingBatches[chainPair]) >= bp.batchSize {
		bp.processBatch(chainPair)
	}
}

// processPendingBatches processes all pending batches
func (bp *BatchProcessor) processPendingBatches() {
	bp.mutex.Lock()
	defer bp.mutex.Unlock()
	
	for chainPair := range bp.pendingBatches {
		if len(bp.pendingBatches[chainPair]) > 0 {
			bp.processBatch(chainPair)
		}
	}
}

// processBatch processes a batch of tasks for a specific chain pair
func (bp *BatchProcessor) processBatch(chainPair string) {
	batch := bp.pendingBatches[chainPair]
	bp.pendingBatches[chainPair] = nil
	
	bp.logger.Info("Processing batch",
		"chainPair", chainPair,
		"batchSize", len(batch),
	)
	
	// In a real implementation, this would optimize the batch execution
	// For now, we'll process them individually
	// TODO: Implement actual batch optimization logic
}

// HealthChecker methods

// start begins health monitoring
func (hc *HealthChecker) start(ctx context.Context, processor *TaskProcessor) {
	ticker := time.NewTicker(60 * time.Second)
	defer ticker.Stop()
	
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			hc.checkHealth(processor)
		}
	}
}

// checkHealth performs health checks on the processor
func (hc *HealthChecker) checkHealth(processor *TaskProcessor) {
	hc.lastHealthCheck = time.Now()
	
	// Check if workers are responsive
	activeWorkers := 0
	for _, worker := range processor.workerPool {
		if worker.isActive && time.Since(worker.lastActivity) < 2*time.Minute {
			activeWorkers++
		}
	}
	
	// Check queue depths
	pendingCount := len(processor.pendingTasks)
	priorityCount := len(processor.priorityTasks)
	
	// Check for concerning conditions
	isHealthy := true
	if activeWorkers == 0 {
		hc.logger.Warn("No active workers detected")
		isHealthy = false
	}
	
	if pendingCount > 500 {
		hc.logger.Warn("High pending task count", "count", pendingCount)
		isHealthy = false
	}
	
	if isHealthy {
		hc.consecutiveErrors = 0
	} else {
		hc.consecutiveErrors++
	}
	
	hc.isHealthy = hc.consecutiveErrors < hc.maxErrorThreshold
	
	hc.logger.Debug("Health check completed",
		"isHealthy", hc.isHealthy,
		"activeWorkers", activeWorkers,
		"pendingTasks", pendingCount,
		"priorityTasks", priorityCount,
		"consecutiveErrors", hc.consecutiveErrors,
	)
}

// IsHealthy returns the current health status
func (hc *HealthChecker) IsHealthy() bool {
	return hc.isHealthy
}