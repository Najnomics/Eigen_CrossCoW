package across

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/Layr-Labs/eigensdk-go/logging"
	"github.com/ethereum/go-ethereum/common"
)

// BridgeMonitor monitors the status of cross-chain bridges
type BridgeMonitor struct {
	logger           logging.Logger
	monitorInterval  time.Duration
	activeBridges    map[uint32]*BridgeMonitoringInfo
	mutex            sync.RWMutex
	eventCallbacks   map[string]BridgeEventCallback
	metricsCollector *BridgeMetrics
}

// BridgeMonitoringInfo holds information about a bridge being monitored
type BridgeMonitoringInfo struct {
	DepositId        uint32        `json:"depositId"`
	OriginChain      uint32        `json:"originChain"`
	DestinationChain uint32        `json:"destinationChain"`
	Amount           string        `json:"amount"`
	Status           BridgeStatus  `json:"status"`
	StartTime        time.Time     `json:"startTime"`
	LastUpdate       time.Time     `json:"lastUpdate"`
	ExpectedTime     time.Duration `json:"expectedTime"`
	Retries          int           `json:"retries"`
	TransactionHash  common.Hash   `json:"transactionHash"`
}

// BridgeStatus represents the current status of a bridge
type BridgeStatus string

const (
	StatusPending    BridgeStatus = "pending"
	StatusConfirmed  BridgeStatus = "confirmed"
	StatusFilling    BridgeStatus = "filling"
	StatusCompleted  BridgeStatus = "completed"
	StatusFailed     BridgeStatus = "failed"
	StatusTimeout    BridgeStatus = "timeout"
)

// BridgeEventCallback is called when bridge events occur
type BridgeEventCallback func(depositId uint32, status BridgeStatus, info *BridgeMonitoringInfo)

// BridgeMetrics collects bridge performance metrics
type BridgeMetrics struct {
	TotalBridges      int64         `json:"totalBridges"`
	CompletedBridges  int64         `json:"completedBridges"`
	FailedBridges     int64         `json:"failedBridges"`
	AverageTime       time.Duration `json:"averageTime"`
	TimeoutCount      int64         `json:"timeoutCount"`
	mutex             sync.RWMutex
}

// NewBridgeMonitor creates a new bridge monitor
func NewBridgeMonitor(monitorInterval time.Duration, logger logging.Logger) *BridgeMonitor {
	return &BridgeMonitor{
		logger:           logger.With("component", "bridge-monitor"),
		monitorInterval:  monitorInterval,
		activeBridges:    make(map[uint32]*BridgeMonitoringInfo),
		eventCallbacks:   make(map[string]BridgeEventCallback),
		metricsCollector: &BridgeMetrics{},
	}
}

// Start begins monitoring bridges
func (bm *BridgeMonitor) Start(ctx context.Context) error {
	bm.logger.Info("Starting bridge monitor", "interval", bm.monitorInterval)
	
	ticker := time.NewTicker(bm.monitorInterval)
	defer ticker.Stop()
	
	for {
		select {
		case <-ctx.Done():
			bm.logger.Info("Bridge monitor shutting down")
			return nil
		case <-ticker.C:
			bm.monitorActiveBridges()
		}
	}
}

// AddBridge adds a new bridge to monitor
func (bm *BridgeMonitor) AddBridge(depositId uint32, originChain, destChain uint32, amount string, txHash common.Hash, expectedTime time.Duration) {
	bm.mutex.Lock()
	defer bm.mutex.Unlock()
	
	info := &BridgeMonitoringInfo{
		DepositId:        depositId,
		OriginChain:      originChain,
		DestinationChain: destChain,
		Amount:          amount,
		Status:          StatusPending,
		StartTime:       time.Now(),
		LastUpdate:      time.Now(),
		ExpectedTime:    expectedTime,
		Retries:         0,
		TransactionHash: txHash,
	}
	
	bm.activeBridges[depositId] = info
	bm.metricsCollector.TotalBridges++
	
	bm.logger.Info("Added bridge to monitor",
		"depositId", depositId,
		"originChain", originChain,
		"destChain", destChain,
		"amount", amount,
	)
	
	// Trigger callback for new bridge
	bm.triggerCallbacks(depositId, StatusPending, info)
}

// RemoveBridge removes a bridge from monitoring
func (bm *BridgeMonitor) RemoveBridge(depositId uint32) {
	bm.mutex.Lock()
	defer bm.mutex.Unlock()
	
	if info, exists := bm.activeBridges[depositId]; exists {
		delete(bm.activeBridges, depositId)
		bm.logger.Info("Removed bridge from monitoring",
			"depositId", depositId,
			"finalStatus", info.Status,
			"duration", time.Since(info.StartTime),
		)
	}
}

// GetBridgeStatus returns the current status of a bridge
func (bm *BridgeMonitor) GetBridgeStatus(depositId uint32) (BridgeStatus, *BridgeMonitoringInfo, bool) {
	bm.mutex.RLock()
	defer bm.mutex.RUnlock()
	
	if info, exists := bm.activeBridges[depositId]; exists {
		return info.Status, info, true
	}
	
	return "", nil, false
}

// GetActiveBridges returns all currently monitored bridges
func (bm *BridgeMonitor) GetActiveBridges() map[uint32]*BridgeMonitoringInfo {
	bm.mutex.RLock()
	defer bm.mutex.RUnlock()
	
	bridges := make(map[uint32]*BridgeMonitoringInfo)
	for id, info := range bm.activeBridges {
		bridges[id] = info
	}
	
	return bridges
}

// RegisterCallback registers a callback for bridge events
func (bm *BridgeMonitor) RegisterCallback(name string, callback BridgeEventCallback) {
	bm.mutex.Lock()
	defer bm.mutex.Unlock()
	
	bm.eventCallbacks[name] = callback
	bm.logger.Info("Registered bridge event callback", "name", name)
}

// UnregisterCallback removes a callback
func (bm *BridgeMonitor) UnregisterCallback(name string) {
	bm.mutex.Lock()
	defer bm.mutex.Unlock()
	
	delete(bm.eventCallbacks, name)
	bm.logger.Info("Unregistered bridge event callback", "name", name)
}

// GetMetrics returns current bridge metrics
func (bm *BridgeMonitor) GetMetrics() *BridgeMetrics {
	bm.metricsCollector.mutex.RLock()
	defer bm.metricsCollector.mutex.RUnlock()
	
	metrics := *bm.metricsCollector
	return &metrics
}

// monitorActiveBridges checks the status of all active bridges
func (bm *BridgeMonitor) monitorActiveBridges() {
	bm.mutex.Lock()
	defer bm.mutex.Unlock()
	
	now := time.Now()
	
	for depositId, info := range bm.activeBridges {
		// Check if bridge has timed out
		if now.Sub(info.StartTime) > info.ExpectedTime*2 {
			bm.updateBridgeStatus(depositId, StatusTimeout, "Bridge exceeded expected time")
			continue
		}
		
		// Check bridge status on destination chain
		newStatus, err := bm.checkBridgeOnChain(info)
		if err != nil {
			bm.logger.Warn("Error checking bridge status",
				"depositId", depositId,
				"error", err,
			)
			info.Retries++
			continue
		}
		
		if newStatus != info.Status {
			bm.updateBridgeStatus(depositId, newStatus, "Status updated from chain")
		}
	}
}

// checkBridgeOnChain checks the actual status of a bridge on the blockchain
func (bm *BridgeMonitor) checkBridgeOnChain(info *BridgeMonitoringInfo) (BridgeStatus, error) {
	// In a real implementation, this would:
	// 1. Query the destination chain spoke pool for fill events
	// 2. Check transaction confirmations
	// 3. Verify successful execution
	
	// For now, simulate status progression
	timeSinceStart := time.Since(info.StartTime)
	
	switch info.Status {
	case StatusPending:
		if timeSinceStart > 30*time.Second {
			return StatusConfirmed, nil
		}
	case StatusConfirmed:
		if timeSinceStart > 1*time.Minute {
			return StatusFilling, nil
		}
	case StatusFilling:
		if timeSinceStart > info.ExpectedTime {
			return StatusCompleted, nil
		}
	}
	
	return info.Status, nil
}

// updateBridgeStatus updates the status of a bridge and triggers callbacks
func (bm *BridgeMonitor) updateBridgeStatus(depositId uint32, status BridgeStatus, reason string) {
	info := bm.activeBridges[depositId]
	if info == nil {
		return
	}
	
	oldStatus := info.Status
	info.Status = status
	info.LastUpdate = time.Now()
	
	bm.logger.Info("Bridge status updated",
		"depositId", depositId,
		"oldStatus", oldStatus,
		"newStatus", status,
		"reason", reason,
	)
	
	// Update metrics
	switch status {
	case StatusCompleted:
		bm.metricsCollector.mutex.Lock()
		bm.metricsCollector.CompletedBridges++
		
		// Update average time
		duration := time.Since(info.StartTime)
		if bm.metricsCollector.CompletedBridges == 1 {
			bm.metricsCollector.AverageTime = duration
		} else {
			// Rolling average
			bm.metricsCollector.AverageTime = (bm.metricsCollector.AverageTime*time.Duration(bm.metricsCollector.CompletedBridges-1) + duration) / time.Duration(bm.metricsCollector.CompletedBridges)
		}
		bm.metricsCollector.mutex.Unlock()
		
	case StatusFailed:
		bm.metricsCollector.mutex.Lock()
		bm.metricsCollector.FailedBridges++
		bm.metricsCollector.mutex.Unlock()
		
	case StatusTimeout:
		bm.metricsCollector.mutex.Lock()
		bm.metricsCollector.TimeoutCount++
		bm.metricsCollector.FailedBridges++
		bm.metricsCollector.mutex.Unlock()
	}
	
	// Trigger callbacks
	bm.triggerCallbacks(depositId, status, info)
	
	// Remove completed or failed bridges after a delay
	if status == StatusCompleted || status == StatusFailed || status == StatusTimeout {
		go func() {
			time.Sleep(5 * time.Minute) // Keep for 5 minutes for querying
			bm.RemoveBridge(depositId)
		}()
	}
}

// triggerCallbacks calls all registered callbacks for a bridge event
func (bm *BridgeMonitor) triggerCallbacks(depositId uint32, status BridgeStatus, info *BridgeMonitoringInfo) {
	for name, callback := range bm.eventCallbacks {
		go func(name string, cb BridgeEventCallback) {
			defer func() {
				if r := recover(); r != nil {
					bm.logger.Error("Bridge callback panicked",
						"callback", name,
						"depositId", depositId,
						"error", r,
					)
				}
			}()
			
			cb(depositId, status, info)
		}(name, callback)
	}
}

// GetBridgeHistory returns completed bridge information (would be stored in database in production)
func (bm *BridgeMonitor) GetBridgeHistory(limit int) []*BridgeMonitoringInfo {
	// In production, this would query a database for historical bridge data
	// For now, return empty slice
	return []*BridgeMonitoringInfo{}
}

// EstimateCompletionTime estimates when a bridge will complete based on historical data
func (bm *BridgeMonitor) EstimateCompletionTime(originChain, destChain uint32, amount string) time.Duration {
	// In production, this would analyze historical data for similar bridges
	// For now, return basic estimates
	
	baseTimes := map[string]time.Duration{
		"1-10":    2 * time.Minute,  // ETH -> Optimism
		"1-137":   5 * time.Minute,  // ETH -> Polygon
		"1-42161": 3 * time.Minute,  // ETH -> Arbitrum
		"1-8453":  2 * time.Minute,  // ETH -> Base
		"10-1":    15 * time.Minute, // Optimism -> ETH
		"137-1":   30 * time.Minute, // Polygon -> ETH
		"42161-1": 15 * time.Minute, // Arbitrum -> ETH
		"8453-1":  15 * time.Minute, // Base -> ETH
	}
	
	key := fmt.Sprintf("%d-%d", originChain, destChain)
	if duration, exists := baseTimes[key]; exists {
		return duration
	}
	
	return 10 * time.Minute // Default estimate
}