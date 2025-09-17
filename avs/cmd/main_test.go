package main

import (
	"encoding/json"
	"testing"

	performerV1 "github.com/Layr-Labs/protocol-apis/gen/protos/eigenlayer/hourglass/v1/performer"
	"go.uber.org/zap"
)

func Test_CrossCoWTaskRequestPayload(t *testing.T) {
	// ------------------------------------------------------------------------
	// CrossCoW Task Tests
	// ------------------------------------------------------------------------

	logger, err := zap.NewDevelopment()
	if err != nil {
		t.Errorf("Failed to create logger: %v", err)
	}

	performer := NewCrossCoWPerformer(logger)

	// Test basic task validation
	taskRequest := &performerV1.TaskRequest{
		TaskId:  []byte("test-crosscow-task-id"),
		Payload: []byte(`{"type":"intent_matching","parameters":{"intent_id":"0x123","pool_id":"0xabc"}}`),
	}

	err = performer.ValidateTask(taskRequest)
	if err != nil {
		t.Errorf("ValidateTask failed: %v", err)
	}

	resp, err := performer.HandleTask(taskRequest)
	if err != nil {
		t.Errorf("HandleTask failed: %v", err)
	}

	t.Logf("Response: %v", resp)
}

func Test_CrossCoWTaskTypes(t *testing.T) {
	logger, err := zap.NewDevelopment()
	if err != nil {
		t.Errorf("Failed to create logger: %v", err)
	}

	performer := NewCrossCoWPerformer(logger)

	testCases := []struct {
		name     string
		taskType TaskType
		params   map[string]interface{}
	}{
		{
			name:     "Intent Matching Task",
			taskType: TaskTypeIntentMatching,
			params: map[string]interface{}{
				"intent_id": "0x1234567890abcdef",
				"pool_id":   "0xabcdef",
			},
		},
		{
			name:     "Cross-Chain Execution Task",
			taskType: TaskTypeCrossChainExecution,
			params: map[string]interface{}{
				"trade_id":     "0xabcdef",
				"target_chain": 42161,
				"amount":       1000,
			},
		},
		{
			name:     "Trade Validation Task",
			taskType: TaskTypeTradeValidation,
			params: map[string]interface{}{
				"trade_id":  "0x123",
				"amount":    500,
				"signature": "0xbidder",
			},
		},
		{
			name:     "Settlement Task",
			taskType: TaskTypeSettlement,
			params: map[string]interface{}{
				"trade_id": "0x123",
				"winner":   "0xwinner",
				"amount":   1000,
			},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			// Create task payload
			payload := TaskPayload{
				Type:       tc.taskType,
				Parameters: tc.params,
			}

			payloadBytes, err := json.Marshal(payload)
			if err != nil {
				t.Errorf("Failed to marshal payload: %v", err)
				return
			}

			taskRequest := &performerV1.TaskRequest{
				TaskId:  []byte("test-task-" + string(tc.taskType)),
				Payload: payloadBytes,
			}

			// Test validation
			err = performer.ValidateTask(taskRequest)
			if err != nil {
				t.Errorf("ValidateTask failed for %s: %v", tc.name, err)
				return
			}

			// Test handling
			resp, err := performer.HandleTask(taskRequest)
			if err != nil {
				t.Errorf("HandleTask failed for %s: %v", tc.name, err)
				return
			}

			if resp == nil {
				t.Errorf("HandleTask returned nil response for %s", tc.name)
				return
			}

			if len(resp.Result) == 0 {
				t.Errorf("HandleTask returned empty result for %s", tc.name)
				return
			}

			t.Logf("%s completed successfully with result: %s", tc.name, string(resp.Result))
		})
	}
}

func Test_TaskPayloadParsing(t *testing.T) {
	// Test payload parsing functionality
	testPayload := TaskPayload{
		Type: TaskTypeIntentMatching,
		Parameters: map[string]interface{}{
			"intent_id": "0x1234567890abcdef",
			"pool_id":   "0xabcdef",
		},
	}

	payloadBytes, err := json.Marshal(testPayload)
	if err != nil {
		t.Errorf("Failed to marshal test payload: %v", err)
		return
	}

	taskRequest := &performerV1.TaskRequest{
		TaskId:  []byte("parse-test"),
		Payload: payloadBytes,
	}

	parsedPayload, err := parseTaskPayload(taskRequest)
	if err != nil {
		t.Errorf("Failed to parse task payload: %v", err)
		return
	}

	if parsedPayload.Type != TaskTypeIntentMatching {
		t.Errorf("Expected task type %s, got %s", TaskTypeIntentMatching, parsedPayload.Type)
	}

	if parsedPayload.Parameters["pool_id"] != "0xabcdef" {
		t.Errorf("Expected pool_id 0xabcdef, got %v", parsedPayload.Parameters["pool_id"])
	}

	t.Logf("Payload parsing test successful: %+v", parsedPayload)
}