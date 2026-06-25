// Package metrics implements DORA and SPACE framework metrics for the Evergreen
// federation. Tracks deployment frequency, lead time, change failure rate, and
// time to restore (DORA), plus satisfaction, performance, activity,
// communication, and efficiency (SPACE).
//
// Ported from src/protocols/metrics.py.
package metrics

import (
	"sync"
	"time"
)

// ---------------------------------------------------------------------------
// DORA Metrics
// ---------------------------------------------------------------------------

// DORALevel classifies engineering performance per DORA research.
type DORALevel string

const (
	DORAElite       DORALevel = "elite"
	DORAHigh        DORALevel = "high"
	DORAMedium      DORALevel = "medium"
	DORALow         DORALevel = "low"
)

// DORA tracks the four key DORA metrics.
type DORA struct {
	mu                  sync.RWMutex
	deploymentCount     int
	lastDeployment      time.Time
	totalLeadTime       time.Duration // cumulative lead time
	changeCount         int
	failureCount        int
	totalRestoreTime    time.Duration
	restoreCount        int
}

// NewDORA creates a DORA metrics tracker.
func NewDORA() *DORA {
	return &DORA{}
}

// RecordDeployment records a deployment event.
func (d *DORA) RecordDeployment(leadTime time.Duration) {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.deploymentCount++
	d.lastDeployment = time.Now()
	d.totalLeadTime += leadTime
}

// RecordChange records a production change.
func (d *DORA) RecordChange() {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.changeCount++
}

// RecordFailure records a change failure and its restore time.
func (d *DORA) RecordFailure(restoreTime time.Duration) {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.failureCount++
	d.totalRestoreTime += restoreTime
}

// DeploymentFrequency returns deployments per day (approximate).
func (d *DORA) DeploymentFrequency() float64 {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if d.deploymentCount == 0 {
		return 0
	}
	// Simple: total deployments (no time range stored, so return count as-is)
	return float64(d.deploymentCount)
}

// LeadTime returns the average lead time for changes.
func (d *DORA) LeadTime() time.Duration {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if d.deploymentCount == 0 {
		return 0
	}
	return d.totalLeadTime / time.Duration(d.deploymentCount)
}

// ChangeFailureRate returns the ratio of failed to total changes.
func (d *DORA) ChangeFailureRate() float64 {
	d.mu.RLock()
	defer d.mu.RUnlock()
	total := d.changeCount + d.failureCount
	if total == 0 {
		return 0
	}
	return float64(d.failureCount) / float64(total)
}

// TimeToRestore returns the average restore time.
func (d *DORA) TimeToRestore() time.Duration {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if d.restoreCount == 0 {
		return 0
	}
	return d.totalRestoreTime / time.Duration(d.restoreCount)
}

// EliteLevel classifies the organization per DORA elite/high/medium/low tiers.
func (d *DORA) EliteLevel() DORALevel {
	d.mu.RLock()
	defer d.mu.RUnlock()

	freq := d.DeploymentFrequency()
	lead := d.LeadTime()
	failRate := d.ChangeFailureRate()
	restore := d.TimeToRestore()

	// Elite: on-demand deploy, <1h lead, <5% fail, <1h restore
	if freq >= 1 && lead <= time.Hour && failRate <= 0.05 && restore <= time.Hour {
		return DORAElite
	}
	// High: daily-weekly, <1w lead, <10% fail, <1day restore
	if lead <= 7*24*time.Hour && failRate <= 0.10 && restore <= 24*time.Hour {
		return DORAHigh
	}
	// Medium
	if lead <= 30*24*time.Hour && failRate <= 0.15 {
		return DORAMedium
	}
	return DORALow
}

// Summary returns a map of current DORA metrics.
func (d *DORA) Summary() map[string]interface{} {
	return map[string]interface{}{
		"deployment_frequency": d.DeploymentFrequency(),
		"lead_time_ms":         d.LeadTime().Milliseconds(),
		"change_failure_rate":  d.ChangeFailureRate(),
		"time_to_restore_ms":   d.TimeToRestore().Milliseconds(),
		"elite_level":          string(d.EliteLevel()),
		"deployments":          d.deploymentCount,
		"failures":             d.failureCount,
	}
}

// ---------------------------------------------------------------------------
// SPACE Metrics
// ---------------------------------------------------------------------------

// SPACE tracks the SPACE framework dimensions.
type SPACE struct {
	mu              sync.RWMutex
	satisfaction    float64 // aggregate satisfaction score 0-100
	performance     float64 // throughput / velocity
	activity        int     // total actions
	communication   int     // interactions
	efficiency      float64 // ability to complete work
}

// NewSPACE creates a SPACE metrics tracker.
func NewSPACE() *SPACE {
	return &SPACE{}
}

// RecordSatisfaction updates the satisfaction score.
func (s *SPACE) RecordSatisfaction(score float64) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.activity == 0 {
		s.satisfaction = score
	} else {
		// Rolling average
		n := float64(s.activity)
		s.satisfaction = (s.satisfaction*n + score) / (n + 1)
	}
}

// RecordActivity increments the activity counter.
func (s *SPACE) RecordActivity() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.activity++
}

// RecordCommunication increments the communication counter.
func (s *SPACE) RecordCommunication() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.communication++
}

// RecordPerformance updates the performance metric.
func (s *SPACE) RecordPerformance(throughput float64) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.performance = throughput
}

// RecordEfficiency updates the efficiency metric (0-100).
func (s *SPACE) RecordEfficiency(score float64) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.efficiency = score
}

// Summary returns a map of current SPACE metrics.
func (s *SPACE) Summary() map[string]interface{} {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return map[string]interface{}{
		"satisfaction":  s.satisfaction,
		"performance":   s.performance,
		"activity":      s.activity,
		"communication": s.communication,
		"efficiency":    s.efficiency,
	}
}

// ---------------------------------------------------------------------------
// Federation Collector
// ---------------------------------------------------------------------------

// Collector aggregates DORA and SPACE metrics for the entire federation.
type Collector struct {
	dora  *DORA
	space *SPACE
}

// NewCollector creates a combined metrics collector.
func NewCollector() *Collector {
	return &Collector{
		dora:  NewDORA(),
		space: NewSPACE(),
	}
}

// DORA returns the DORA metrics tracker.
func (c *Collector) DORA() *DORA { return c.dora }

// SPACE returns the SPACE metrics tracker.
func (c *Collector) SPACE() *SPACE { return c.space }

// FederationSummary returns a complete metrics snapshot.
func (c *Collector) FederationSummary() map[string]interface{} {
	return map[string]interface{}{
		"dora":  c.dora.Summary(),
		"space": c.space.Summary(),
	}
}
