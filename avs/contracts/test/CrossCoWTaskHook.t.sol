// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {CrossCoWTaskHook} from "../src/l2-contracts/CrossCoWTaskHook.sol";
import {ITaskMailboxTypes} from "@eigenlayer-contracts/src/contracts/interfaces/ITaskMailbox.sol";

contract CrossCoWTaskHookTest is Test {
    CrossCoWTaskHook public taskHook;
    
    // Mock addresses
    address public constant MOCK_CROSSCOW_HOOK = address(0x1);
    address public constant MOCK_SERVICE_MANAGER = address(0x2);
    address public constant MOCK_CALLER = address(0x3);
    
    function setUp() public {
        taskHook = new CrossCoWTaskHook(MOCK_CROSSCOW_HOOK, MOCK_SERVICE_MANAGER);
        
        vm.label(MOCK_CROSSCOW_HOOK, "MainCrossCoWHook");
        vm.label(MOCK_SERVICE_MANAGER, "ServiceManager");
        vm.label(MOCK_CALLER, "TaskCaller");
    }
    
    function testTaskHookDeployment() public {
        assertEq(taskHook.getCrossCoWHook(), MOCK_CROSSCOW_HOOK);
        console.log("Task hook correctly references main CrossCoW hook");
    }
    
    function testTaskTypeConstants() public {
        bytes32[] memory supportedTypes = taskHook.getSupportedTaskTypes();
        
        assertEq(supportedTypes.length, 4);
        console.log("Supports 4 CrossCoW task types");
        
        // Test that task types are properly defined
        assertTrue(supportedTypes[0] != bytes32(0), "INTENT_MATCHING type defined");
        assertTrue(supportedTypes[1] != bytes32(0), "CROSS_CHAIN_EXECUTION type defined");
        assertTrue(supportedTypes[2] != bytes32(0), "TRADE_VALIDATION type defined");
        assertTrue(supportedTypes[3] != bytes32(0), "SETTLEMENT type defined");
    }
    
    function testTaskFeeStructure() public {
        bytes32 intentMatchingType = keccak256("INTENT_MATCHING");
        uint96 fee = taskHook.getTaskTypeFee(intentMatchingType);
        
        assertGt(fee, 0, "Intent matching task should have non-zero fee");
        console.log("CrossCoW intent matching task fee:", fee);
        
        bytes32 settlementType = keccak256("SETTLEMENT");
        uint96 settlementFee = taskHook.getTaskTypeFee(settlementType);
        
        assertGt(settlementFee, fee, "Settlement should cost more than intent matching");
        console.log("Settlement task fee:", settlementFee);
    }
    
    function testTaskValidationBasic() public {
        // Create a minimal task params structure
        bytes memory payload = abi.encodePacked(keccak256("INTENT_MATCHING"));
        
        ITaskMailboxTypes.TaskParams memory taskParams = ITaskMailboxTypes.TaskParams({
            payload: payload
        });
        
        // This should not revert for valid task type
        try taskHook.validatePreTaskCreation(MOCK_CALLER, taskParams) {
            console.log("Basic task validation passed");
        } catch {
            fail("Basic task validation should not revert");
        }
    }
    
    function testConnectorPattern() public {
        // Test that this is a connector, not business logic
        console.log("Testing L2 connector pattern");
        
        // The task hook should:
        // 1. Interface with EigenLayer task system
        // 2. Reference the main CrossCoW hook (business logic)
        // 3. NOT implement CrossCoW logic itself
        
        assertEq(taskHook.getCrossCoWHook(), MOCK_CROSSCOW_HOOK, "Should reference main hook");
        
        // Test that it calculates fees (coordination function)
        bytes memory payload = abi.encodePacked(keccak256("INTENT_MATCHING"));
        ITaskMailboxTypes.TaskParams memory taskParams = ITaskMailboxTypes.TaskParams({
            payload: payload
        });
        
        uint96 fee = taskHook.calculateTaskFee(taskParams);
        assertGt(fee, 0, "Should calculate task fees");
        
        console.log("L2 connector pattern test passed");
    }
    
    function testInvalidTaskType() public {
        bytes memory invalidPayload = abi.encodePacked(keccak256("INVALID_TYPE"));
        
        ITaskMailboxTypes.TaskParams memory taskParams = ITaskMailboxTypes.TaskParams({
            payload: invalidPayload
        });
        
        // Should revert for unsupported task type
        vm.expectRevert("Unsupported task type");
        taskHook.validatePreTaskCreation(MOCK_CALLER, taskParams);
        
        console.log("Invalid task type properly rejected");
    }
    
    function testCrossCoWTaskTypes() public {
        // Test all CrossCoW task type constants
        bytes32 intentMatching = taskHook.TASK_TYPE_INTENT_MATCHING();
        bytes32 crossChainExecution = taskHook.TASK_TYPE_CROSS_CHAIN_EXECUTION();
        bytes32 tradeValidation = taskHook.TASK_TYPE_TRADE_VALIDATION();
        bytes32 settlement = taskHook.TASK_TYPE_SETTLEMENT();
        
        assertTrue(intentMatching != bytes32(0), "Intent matching type defined");
        assertTrue(crossChainExecution != bytes32(0), "Cross-chain execution type defined");
        assertTrue(tradeValidation != bytes32(0), "Trade validation type defined");
        assertTrue(settlement != bytes32(0), "Settlement type defined");
        
        console.log("All CrossCoW task types properly defined");
    }
}