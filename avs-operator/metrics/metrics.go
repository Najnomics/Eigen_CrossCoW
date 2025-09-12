package metrics

import (
	"context"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/Layr-Labs/eigensdk-go/metrics"
)

// Metrics defines the metrics interface
type Metrics interface {
	Start(ctx context.Context, reg *prometheus.Registry)
	GetErrChan() <-chan error
	IncNumTasksReceived()
	IncNumTasksProcessed()
	IncNumMatchesFound(count int)
	RecordTaskProcessingTime(duration time.Duration)
	RecordMatchingTime(duration time.Duration)
}

// AvsAndEigenMetrics implements Metrics interface
type AvsAndEigenMetrics struct {
	eigenMetrics metrics.Metrics
	reg          *prometheus.Registry
	
	// Custom metrics
	numTasksReceived    prometheus.Counter
	numTasksProcessed   prometheus.Counter
	numMatchesFound     prometheus.Counter
	taskProcessingTime  prometheus.Histogram
	matchingTime        prometheus.Histogram
}

// NewAvsAndEigenMetrics creates a new metrics instance
func NewAvsAndEigenMetrics(avsName string, eigenMetrics metrics.Metrics, reg *prometheus.Registry) *AvsAndEigenMetrics {
	return &AvsAndEigenMetrics{
		eigenMetrics: eigenMetrics,
		reg:          reg,
		numTasksReceived: promauto.With(reg).NewCounter(prometheus.CounterOpts{
			Name: "avs_tasks_received_total",
			Help: "Total number of tasks received",
		}),
		numTasksProcessed: promauto.With(reg).NewCounter(prometheus.CounterOpts{
			Name: "avs_tasks_processed_total",
			Help: "Total number of tasks processed",
		}),
		numMatchesFound: promauto.With(reg).NewCounter(prometheus.CounterOpts{
			Name: "avs_matches_found_total",
			Help: "Total number of matches found",
		}),
		taskProcessingTime: promauto.With(reg).NewHistogram(prometheus.HistogramOpts{
			Name: "avs_task_processing_duration_seconds",
			Help: "Time spent processing tasks",
		}),
		matchingTime: promauto.With(reg).NewHistogram(prometheus.HistogramOpts{
			Name: "avs_matching_duration_seconds",
			Help: "Time spent on matching algorithm",
		}),
	}
}

func (m *AvsAndEigenMetrics) Start(ctx context.Context, reg *prometheus.Registry) {
	m.eigenMetrics.Start(ctx, reg)
}

func (m *AvsAndEigenMetrics) GetErrChan() <-chan error {
	return m.eigenMetrics.GetErrChan()
}

func (m *AvsAndEigenMetrics) IncNumTasksReceived() {
	m.numTasksReceived.Inc()
}

func (m *AvsAndEigenMetrics) IncNumTasksProcessed() {
	m.numTasksProcessed.Inc()
}

func (m *AvsAndEigenMetrics) IncNumMatchesFound(count int) {
	m.numMatchesFound.Add(float64(count))
}

func (m *AvsAndEigenMetrics) RecordTaskProcessingTime(duration time.Duration) {
	m.taskProcessingTime.Observe(duration.Seconds())
}

func (m *AvsAndEigenMetrics) RecordMatchingTime(duration time.Duration) {
	m.matchingTime.Observe(duration.Seconds())
}
