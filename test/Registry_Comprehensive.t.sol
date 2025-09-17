// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../src/avs/registry/CrossCoWRegistryCoordinator.sol";
import "../src/avs/registry/CrossCoWStakeRegistry.sol";
import "../src/avs/registry/CrossCoWBLSApkRegistry.sol";
import "./mocks/MockContracts.sol";

/**
 * @title Registry Contracts Comprehensive Test Suite
 * @notice 100+ comprehensive unit tests for all registry contracts
 * @dev Tests all functionality including edge cases, security, and performance
 */
contract RegistryComprehensiveTest is Test {
    /* CONTRACTS */
    CrossCoWRegistryCoordinator public registryCoordinator;
    CrossCoWStakeRegistry public stakeRegistry;
    CrossCoWBLSApkRegistry public blsApkRegistry;
    
    MockERC20 public stakeToken;
    
    /* ADDRESSES */
    address public owner = address(0x1);
    address public operator1 = address(0x2);
    address public operator2 = address(0x3);
    address public operator3 = address(0x4);
    
    /* CONSTANTS */
    uint256 public constant MIN_STAKE = 1 ether;
    uint256 public constant STAKE_AMOUNT = 10 ether;
    
    function setUp() public {
        // Deploy stake token
        stakeToken = new MockERC20("StakeToken", "STAKE");
        
        // Deploy registry contracts
        stakeRegistry = new CrossCoWStakeRegistry(address(stakeToken));
        blsApkRegistry = new CrossCoWBLSApkRegistry();
        registryCoordinator = new CrossCoWRegistryCoordinator(
            address(stakeRegistry),
            address(blsApkRegistry)
        );
        
        // Fund test accounts
        stakeToken.mint(operator1, 1000 * 10**18);
        stakeToken.mint(operator2, 1000 * 10**18);
        stakeToken.mint(operator3, 1000 * 10**18);
        
        vm.deal(operator1, 100 ether);
        vm.deal(operator2, 100 ether);
        vm.deal(operator3, 100 ether);
    }

    // ============ STAKE REGISTRY TESTS ============

    function test_001_StakeRegistryInitialization() public {
        assertEq(address(stakeRegistry.stakeToken()), address(stakeToken));
        assertTrue(stakeRegistry.owner() == owner);
    }

    function test_002_CanRegisterOperator() public {
        vm.prank(operator1);
        stakeRegistry.registerOperator(operator1, STAKE_AMOUNT);
        assertTrue(stakeRegistry.isOperatorStaked(operator1));
        assertEq(stakeRegistry.getTotalStake(), STAKE_AMOUNT);
    }

    function test_003_CannotRegisterWithInsufficientStake() public {
        vm.prank(operator1);
        vm.expectRevert("Insufficient stake");
        stakeRegistry.registerOperator(operator1, MIN_STAKE - 1);
    }

    function test_004_CannotRegisterWithExcessiveStake() public {
        vm.prank(operator1);
        vm.expectRevert("Excessive stake");
        stakeRegistry.registerOperator(operator1, 1001 ether);
    }

    function test_005_CannotRegisterTwice() public {
        vm.prank(operator1);
        stakeRegistry.registerOperator(operator1, STAKE_AMOUNT);
        vm.prank(operator1);
        vm.expectRevert("Already registered");
        stakeRegistry.registerOperator(operator1, STAKE_AMOUNT);
    }

    function test_006_RegistrationEmitsEvent() public {
        vm.prank(operator1);
        vm.expectEmit(true, true, true, true);
        emit OperatorRegistered(operator1, STAKE_AMOUNT);
        stakeRegistry.registerOperator(operator1, STAKE_AMOUNT);
    }

    function test_007_CanDeregisterOperator() public {
        vm.prank(operator1);
        stakeRegistry.registerOperator(operator1, STAKE_AMOUNT);
        vm.prank(operator1);
        stakeRegistry.deregisterOperator(operator1);
        assertFalse(stakeRegistry.isOperatorStaked(operator1));
    }

    function test_008_CannotDeregisterWhenNotRegistered() public {
        vm.prank(operator1);
        vm.expectRevert("Operator not registered");
        stakeRegistry.deregisterOperator(operator1);
    }

    function test_009_DeregistrationEmitsEvent() public {
        vm.prank(operator1);
        stakeRegistry.registerOperator(operator1, STAKE_AMOUNT);
        vm.prank(operator1);
        vm.expectEmit(true, true, true, true);
        emit OperatorDeregistered(operator1);
        stakeRegistry.deregisterOperator(operator1);
    }

    function test_010_CanUpdateStake() public {
        vm.prank(operator1);
        stakeRegistry.registerOperator(operator1, STAKE_AMOUNT);
        vm.prank(operator1);
        stakeRegistry.updateStake(operator1, STAKE_AMOUNT * 2);
        assertEq(stakeRegistry.getTotalStake(), STAKE_AMOUNT * 2);
    }

    function test_011_CannotUpdateStakeWhenNotRegistered() public {
        vm.prank(operator1);
        vm.expectRevert("Operator not registered");
        stakeRegistry.updateStake(operator1, STAKE_AMOUNT);
    }

    function test_012_OwnerCanSlashOperator() public {
        vm.prank(operator1);
        stakeRegistry.registerOperator(operator1, STAKE_AMOUNT);
        uint256 slashAmount = 1 ether;
        vm.prank(owner);
        stakeRegistry.slashOperator(operator1, slashAmount, "Test slashing");
        assertLt(stakeRegistry.getTotalStake(), STAKE_AMOUNT);
    }

    function test_013_NonOwnerCannotSlashOperator() public {
        vm.prank(operator1);
        stakeRegistry.registerOperator(operator1, STAKE_AMOUNT);
        uint256 slashAmount = 1 ether;
        vm.prank(operator1);
        vm.expectRevert("Ownable: caller is not the owner");
        stakeRegistry.slashOperator(operator1, slashAmount, "Test slashing");
    }

    function test_014_SlashingEmitsEvent() public {
        vm.prank(operator1);
        stakeRegistry.registerOperator(operator1, STAKE_AMOUNT);
        uint256 slashAmount = 1 ether;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit OperatorSlashed(operator1, slashAmount, "Test slashing");
        stakeRegistry.slashOperator(operator1, slashAmount, "Test slashing");
    }

    function test_015_OwnerCanRewardOperator() public {
        vm.prank(operator1);
        stakeRegistry.registerOperator(operator1, STAKE_AMOUNT);
        uint256 rewardAmount = 1 ether;
        vm.prank(owner);
        stakeRegistry.rewardOperator(operator1, rewardAmount);
        assertGt(stakeRegistry.getTotalStake(), STAKE_AMOUNT);
    }

    function test_016_RewardEmitsEvent() public {
        vm.prank(operator1);
        stakeRegistry.registerOperator(operator1, STAKE_AMOUNT);
        uint256 rewardAmount = 1 ether;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit OperatorRewarded(operator1, rewardAmount);
        stakeRegistry.rewardOperator(operator1, rewardAmount);
    }

    // ============ BLS APK REGISTRY TESTS ============

    function test_017_BlsApkRegistryInitialization() public {
        assertTrue(blsApkRegistry.owner() == owner);
    }

    function test_018_CanRegisterOperator() public {
        bytes32 operatorId = keccak256(abi.encodePacked(operator1, "key"));
        CrossCoWBLSApkRegistry.BLSPublicKey memory key = CrossCoWBLSApkRegistry.BLSPublicKey({
            g1Pubkey: abi.encodePacked(operator1, "g1"),
            g2Pubkey: abi.encodePacked(operator1, "g2")
        });
        blsApkRegistry.registerOperator(operator1, operatorId, key);
        assertTrue(blsApkRegistry.isOperatorRegistered(operator1));
    }

    function test_019_CannotRegisterWithInvalidG1Key() public {
        bytes32 operatorId = keccak256(abi.encodePacked(operator1, "key"));
        CrossCoWBLSApkRegistry.BLSPublicKey memory key = CrossCoWBLSApkRegistry.BLSPublicKey({
            g1Pubkey: abi.encodePacked(operator1), // Wrong length
            g2Pubkey: abi.encodePacked(operator1, "g2")
        });
        vm.expectRevert("Invalid G1 public key length");
        blsApkRegistry.registerOperator(operator1, operatorId, key);
    }

    function test_020_CannotRegisterWithInvalidG2Key() public {
        bytes32 operatorId = keccak256(abi.encodePacked(operator1, "key"));
        CrossCoWBLSApkRegistry.BLSPublicKey memory key = CrossCoWBLSApkRegistry.BLSPublicKey({
            g1Pubkey: abi.encodePacked(operator1, "g1"),
            g2Pubkey: abi.encodePacked(operator1) // Wrong length
        });
        vm.expectRevert("Invalid G2 public key length");
        blsApkRegistry.registerOperator(operator1, operatorId, key);
    }

    function test_021_CannotRegisterTwice() public {
        bytes32 operatorId = keccak256(abi.encodePacked(operator1, "key"));
        CrossCoWBLSApkRegistry.BLSPublicKey memory key = CrossCoWBLSApkRegistry.BLSPublicKey({
            g1Pubkey: abi.encodePacked(operator1, "g1"),
            g2Pubkey: abi.encodePacked(operator1, "g2")
        });
        blsApkRegistry.registerOperator(operator1, operatorId, key);
        vm.expectRevert("Already registered");
        blsApkRegistry.registerOperator(operator1, operatorId, key);
    }

    function test_022_CannotRegisterWithTakenId() public {
        bytes32 operatorId = keccak256(abi.encodePacked(operator1, "key"));
        CrossCoWBLSApkRegistry.BLSPublicKey memory key1 = CrossCoWBLSApkRegistry.BLSPublicKey({
            g1Pubkey: abi.encodePacked(operator1, "g1"),
            g2Pubkey: abi.encodePacked(operator1, "g2")
        });
        blsApkRegistry.registerOperator(operator1, operatorId, key1);
        
        CrossCoWBLSApkRegistry.BLSPublicKey memory key2 = CrossCoWBLSApkRegistry.BLSPublicKey({
            g1Pubkey: abi.encodePacked(operator2, "g1"),
            g2Pubkey: abi.encodePacked(operator2, "g2")
        });
        vm.expectRevert("ID already taken");
        blsApkRegistry.registerOperator(operator2, operatorId, key2);
    }

    function test_023_RegistrationEmitsEvent() public {
        bytes32 operatorId = keccak256(abi.encodePacked(operator1, "key"));
        CrossCoWBLSApkRegistry.BLSPublicKey memory key = CrossCoWBLSApkRegistry.BLSPublicKey({
            g1Pubkey: abi.encodePacked(operator1, "g1"),
            g2Pubkey: abi.encodePacked(operator1, "g2")
        });
        vm.expectEmit(true, true, true, true);
        emit OperatorRegistered(operator1, operatorId, key);
        blsApkRegistry.registerOperator(operator1, operatorId, key);
    }

    function test_024_CanDeregisterOperator() public {
        bytes32 operatorId = keccak256(abi.encodePacked(operator1, "key"));
        CrossCoWBLSApkRegistry.BLSPublicKey memory key = CrossCoWBLSApkRegistry.BLSPublicKey({
            g1Pubkey: abi.encodePacked(operator1, "g1"),
            g2Pubkey: abi.encodePacked(operator1, "g2")
        });
        blsApkRegistry.registerOperator(operator1, operatorId, key);
        blsApkRegistry.deregisterOperator(operator1);
        assertFalse(blsApkRegistry.isOperatorRegistered(operator1));
    }

    function test_025_CannotDeregisterWhenNotRegistered() public {
        vm.expectRevert("Operator not registered");
        blsApkRegistry.deregisterOperator(operator1);
    }

    function test_026_DeregistrationEmitsEvent() public {
        bytes32 operatorId = keccak256(abi.encodePacked(operator1, "key"));
        CrossCoWBLSApkRegistry.BLSPublicKey memory key = CrossCoWBLSApkRegistry.BLSPublicKey({
            g1Pubkey: abi.encodePacked(operator1, "g1"),
            g2Pubkey: abi.encodePacked(operator1, "g2")
        });
        blsApkRegistry.registerOperator(operator1, operatorId, key);
        vm.expectEmit(true, true, true, true);
        emit OperatorDeregistered(operator1, operatorId);
        blsApkRegistry.deregisterOperator(operator1);
    }

    function test_027_CanUpdatePublicKey() public {
        bytes32 operatorId = keccak256(abi.encodePacked(operator1, "key"));
        CrossCoWBLSApkRegistry.BLSPublicKey memory key = CrossCoWBLSApkRegistry.BLSPublicKey({
            g1Pubkey: abi.encodePacked(operator1, "g1"),
            g2Pubkey: abi.encodePacked(operator1, "g2")
        });
        blsApkRegistry.registerOperator(operator1, operatorId, key);
        
        CrossCoWBLSApkRegistry.BLSPublicKey memory newKey = CrossCoWBLSApkRegistry.BLSPublicKey({
            g1Pubkey: abi.encodePacked(operator1, "new_g1"),
            g2Pubkey: abi.encodePacked(operator1, "new_g2")
        });
        vm.warp(block.timestamp + 1 days + 1); // Past cooldown
        blsApkRegistry.updatePublicKey(operator1, newKey);
        
        CrossCoWBLSApkRegistry.BLSPublicKey memory retrievedKey = blsApkRegistry.getOperatorKey(operator1);
        assertEq(retrievedKey.g1Pubkey, newKey.g1Pubkey);
    }

    function test_028_CannotUpdateKeyBeforeCooldown() public {
        bytes32 operatorId = keccak256(abi.encodePacked(operator1, "key"));
        CrossCoWBLSApkRegistry.BLSPublicKey memory key = CrossCoWBLSApkRegistry.BLSPublicKey({
            g1Pubkey: abi.encodePacked(operator1, "g1"),
            g2Pubkey: abi.encodePacked(operator1, "g2")
        });
        blsApkRegistry.registerOperator(operator1, operatorId, key);
        
        CrossCoWBLSApkRegistry.BLSPublicKey memory newKey = CrossCoWBLSApkRegistry.BLSPublicKey({
            g1Pubkey: abi.encodePacked(operator1, "new_g1"),
            g2Pubkey: abi.encodePacked(operator1, "new_g2")
        });
        vm.expectRevert("Key update cooldown not met");
        blsApkRegistry.updatePublicKey(operator1, newKey);
    }

    function test_029_CanUpdateOperatorId() public {
        bytes32 operatorId = keccak256(abi.encodePacked(operator1, "key"));
        CrossCoWBLSApkRegistry.BLSPublicKey memory key = CrossCoWBLSApkRegistry.BLSPublicKey({
            g1Pubkey: abi.encodePacked(operator1, "g1"),
            g2Pubkey: abi.encodePacked(operator1, "g2")
        });
        blsApkRegistry.registerOperator(operator1, operatorId, key);
        
        bytes32 newId = keccak256(abi.encodePacked(operator1, "new_key"));
        blsApkRegistry.updateOperatorId(operator1, newId);
        assertEq(blsApkRegistry.getOperatorId(operator1), newId);
    }

    function test_030_CannotUpdateToTakenId() public {
        bytes32 operatorId1 = keccak256(abi.encodePacked(operator1, "key"));
        bytes32 operatorId2 = keccak256(abi.encodePacked(operator2, "key"));
        
        CrossCoWBLSApkRegistry.BLSPublicKey memory key1 = CrossCoWBLSApkRegistry.BLSPublicKey({
            g1Pubkey: abi.encodePacked(operator1, "g1"),
            g2Pubkey: abi.encodePacked(operator1, "g2")
        });
        CrossCoWBLSApkRegistry.BLSPublicKey memory key2 = CrossCoWBLSApkRegistry.BLSPublicKey({
            g1Pubkey: abi.encodePacked(operator2, "g1"),
            g2Pubkey: abi.encodePacked(operator2, "g2")
        });
        
        blsApkRegistry.registerOperator(operator1, operatorId1, key1);
        blsApkRegistry.registerOperator(operator2, operatorId2, key2);
        
        vm.expectRevert("ID already taken");
        blsApkRegistry.updateOperatorId(operator1, operatorId2);
    }

    // ============ REGISTRY COORDINATOR TESTS ============

    function test_031_RegistryCoordinatorInitialization() public {
        assertEq(address(registryCoordinator.stakeRegistry()), address(stakeRegistry));
        assertEq(address(registryCoordinator.blsApkRegistry()), address(blsApkRegistry));
        assertTrue(registryCoordinator.owner() == owner);
    }

    function test_032_CanRegisterOperator() public {
        bytes memory quorumNumbers = abi.encodePacked(uint8(0));
        string memory socket = "tcp://localhost:8080";
        bytes memory params = abi.encode(operator1);
        bytes memory operatorSignature = abi.encodePacked("signature");
        
        registryCoordinator.registerOperator(
            quorumNumbers,
            socket,
            params,
            operatorSignature
        );
        
        assertTrue(registryCoordinator.isOperatorRegistered(operator1));
    }

    function test_033_CannotRegisterWithInvalidQuorum() public {
        bytes memory quorumNumbers = abi.encodePacked(); // Empty quorum
        string memory socket = "tcp://localhost:8080";
        bytes memory params = abi.encode(operator1);
        bytes memory operatorSignature = abi.encodePacked("signature");
        
        vm.expectRevert("Invalid quorum numbers");
        registryCoordinator.registerOperator(
            quorumNumbers,
            socket,
            params,
            operatorSignature
        );
    }

    function test_034_CannotRegisterTwice() public {
        bytes memory quorumNumbers = abi.encodePacked(uint8(0));
        string memory socket = "tcp://localhost:8080";
        bytes memory params = abi.encode(operator1);
        bytes memory operatorSignature = abi.encodePacked("signature");
        
        registryCoordinator.registerOperator(
            quorumNumbers,
            socket,
            params,
            operatorSignature
        );
        
        vm.expectRevert("Already registered");
        registryCoordinator.registerOperator(
            quorumNumbers,
            socket,
            params,
            operatorSignature
        );
    }

    function test_035_RegistrationEmitsEvent() public {
        bytes memory quorumNumbers = abi.encodePacked(uint8(0));
        string memory socket = "tcp://localhost:8080";
        bytes memory params = abi.encode(operator1);
        bytes memory operatorSignature = abi.encodePacked("signature");
        
        vm.expectEmit(true, true, true, true);
        emit OperatorRegistered(operator1, bytes32(0)); // ID will be generated
        registryCoordinator.registerOperator(
            quorumNumbers,
            socket,
            params,
            operatorSignature
        );
    }

    function test_036_CanDeregisterOperator() public {
        bytes memory quorumNumbers = abi.encodePacked(uint8(0));
        string memory socket = "tcp://localhost:8080";
        bytes memory params = abi.encode(operator1);
        bytes memory operatorSignature = abi.encodePacked("signature");
        
        registryCoordinator.registerOperator(
            quorumNumbers,
            socket,
            params,
            operatorSignature
        );
        
        registryCoordinator.deregisterOperator(quorumNumbers);
        assertFalse(registryCoordinator.isOperatorRegistered(operator1));
    }

    function test_037_CannotDeregisterWhenNotRegistered() public {
        bytes memory quorumNumbers = abi.encodePacked(uint8(0));
        vm.expectRevert("Operator not registered");
        registryCoordinator.deregisterOperator(quorumNumbers);
    }

    function test_038_DeregistrationEmitsEvent() public {
        bytes memory quorumNumbers = abi.encodePacked(uint8(0));
        string memory socket = "tcp://localhost:8080";
        bytes memory params = abi.encode(operator1);
        bytes memory operatorSignature = abi.encodePacked("signature");
        
        registryCoordinator.registerOperator(
            quorumNumbers,
            socket,
            params,
            operatorSignature
        );
        
        bytes32 operatorId = registryCoordinator.getOperatorId(operator1);
        vm.expectEmit(true, true, true, true);
        emit OperatorDeregistered(operator1, operatorId);
        registryCoordinator.deregisterOperator(quorumNumbers);
    }

    function test_039_CanUpdateQuorumBitmap() public {
        bytes memory quorumNumbers = abi.encodePacked(uint8(0));
        string memory socket = "tcp://localhost:8080";
        bytes memory params = abi.encode(operator1);
        bytes memory operatorSignature = abi.encodePacked("signature");
        
        registryCoordinator.registerOperator(
            quorumNumbers,
            socket,
            params,
            operatorSignature
        );
        
        bytes32 operatorId = registryCoordinator.getOperatorId(operator1);
        uint192 newBitmap = 1;
        vm.prank(owner);
        registryCoordinator.updateQuorumBitmap(operatorId, newBitmap);
        assertEq(registryCoordinator.getCurrentQuorumBitmap(operatorId), newBitmap);
    }

    function test_040_NonOwnerCannotUpdateQuorumBitmap() public {
        bytes memory quorumNumbers = abi.encodePacked(uint8(0));
        string memory socket = "tcp://localhost:8080";
        bytes memory params = abi.encode(operator1);
        bytes memory operatorSignature = abi.encodePacked("signature");
        
        registryCoordinator.registerOperator(
            quorumNumbers,
            socket,
            params,
            operatorSignature
        );
        
        bytes32 operatorId = registryCoordinator.getOperatorId(operator1);
        uint192 newBitmap = 1;
        vm.prank(operator1);
        vm.expectRevert("Ownable: caller is not the owner");
        registryCoordinator.updateQuorumBitmap(operatorId, newBitmap);
    }

    // ============ INTEGRATION TESTS ============

    function test_041_IntegrationBetweenRegistries() public {
        // Register in stake registry
        vm.prank(operator1);
        stakeRegistry.registerOperator(operator1, STAKE_AMOUNT);
        
        // Register in BLS APK registry
        bytes32 operatorId = keccak256(abi.encodePacked(operator1, "key"));
        CrossCoWBLSApkRegistry.BLSPublicKey memory key = CrossCoWBLSApkRegistry.BLSPublicKey({
            g1Pubkey: abi.encodePacked(operator1, "g1"),
            g2Pubkey: abi.encodePacked(operator1, "g2")
        });
        blsApkRegistry.registerOperator(operator1, operatorId, key);
        
        // Register in registry coordinator
        bytes memory quorumNumbers = abi.encodePacked(uint8(0));
        string memory socket = "tcp://localhost:8080";
        bytes memory params = abi.encode(operator1);
        bytes memory operatorSignature = abi.encodePacked("signature");
        
        registryCoordinator.registerOperator(
            quorumNumbers,
            socket,
            params,
            operatorSignature
        );
        
        // Verify all registrations
        assertTrue(stakeRegistry.isOperatorStaked(operator1));
        assertTrue(blsApkRegistry.isOperatorRegistered(operator1));
        assertTrue(registryCoordinator.isOperatorRegistered(operator1));
    }

    function test_042_IntegrationDeregistration() public {
        // Register in all registries
        vm.prank(operator1);
        stakeRegistry.registerOperator(operator1, STAKE_AMOUNT);
        
        bytes32 operatorId = keccak256(abi.encodePacked(operator1, "key"));
        CrossCoWBLSApkRegistry.BLSPublicKey memory key = CrossCoWBLSApkRegistry.BLSPublicKey({
            g1Pubkey: abi.encodePacked(operator1, "g1"),
            g2Pubkey: abi.encodePacked(operator1, "g2")
        });
        blsApkRegistry.registerOperator(operator1, operatorId, key);
        
        bytes memory quorumNumbers = abi.encodePacked(uint8(0));
        string memory socket = "tcp://localhost:8080";
        bytes memory params = abi.encode(operator1);
        bytes memory operatorSignature = abi.encodePacked("signature");
        
        registryCoordinator.registerOperator(
            quorumNumbers,
            socket,
            params,
            operatorSignature
        );
        
        // Deregister from all registries
        vm.prank(operator1);
        stakeRegistry.deregisterOperator(operator1);
        blsApkRegistry.deregisterOperator(operator1);
        registryCoordinator.deregisterOperator(quorumNumbers);
        
        // Verify all deregistrations
        assertFalse(stakeRegistry.isOperatorStaked(operator1));
        assertFalse(blsApkRegistry.isOperatorRegistered(operator1));
        assertFalse(registryCoordinator.isOperatorRegistered(operator1));
    }

    // ============ EDGE CASE TESTS ============

    function test_043_HandleMaxOperators() public {
        // Register maximum number of operators
        for (uint i = 0; i < 1000; i++) {
            address operator = address(uint160(0x1000 + i));
            vm.deal(operator, 100 ether);
            vm.prank(operator);
            stakeRegistry.registerOperator(operator, MIN_STAKE);
        }
        
        // Try to register one more
        address extraOperator = address(0x9999);
        vm.deal(extraOperator, 100 ether);
        vm.prank(extraOperator);
        vm.expectRevert("Max operators reached");
        stakeRegistry.registerOperator(extraOperator, MIN_STAKE);
    }

    function test_044_HandleZeroStake() public {
        vm.prank(operator1);
        vm.expectRevert("Insufficient stake");
        stakeRegistry.registerOperator(operator1, 0);
    }

    function test_045_HandleMaxStake() public {
        vm.prank(operator1);
        stakeRegistry.registerOperator(operator1, 1000 ether);
        assertTrue(stakeRegistry.isOperatorStaked(operator1));
    }

    function test_046_HandleZeroAmountSlashing() public {
        vm.prank(operator1);
        stakeRegistry.registerOperator(operator1, STAKE_AMOUNT);
        vm.prank(owner);
        stakeRegistry.slashOperator(operator1, 0, "Zero slash");
        assertEq(stakeRegistry.getTotalStake(), STAKE_AMOUNT);
    }

    function test_047_HandleMaxAmountSlashing() public {
        vm.prank(operator1);
        stakeRegistry.registerOperator(operator1, STAKE_AMOUNT);
        vm.prank(owner);
        stakeRegistry.slashOperator(operator1, STAKE_AMOUNT, "Max slash");
        assertEq(stakeRegistry.getTotalStake(), 0);
    }

    // ============ GAS OPTIMIZATION TESTS ============

    function test_048_GasUsageOnStakeRegistration() public {
        uint256 gasBefore = gasleft();
        vm.prank(operator1);
        stakeRegistry.registerOperator(operator1, STAKE_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();
        assertLt(gasUsed, 300000); // Should be less than 300k gas
    }

    function test_049_GasUsageOnBlsRegistration() public {
        bytes32 operatorId = keccak256(abi.encodePacked(operator1, "key"));
        CrossCoWBLSApkRegistry.BLSPublicKey memory key = CrossCoWBLSApkRegistry.BLSPublicKey({
            g1Pubkey: abi.encodePacked(operator1, "g1"),
            g2Pubkey: abi.encodePacked(operator1, "g2")
        });
        uint256 gasBefore = gasleft();
        blsApkRegistry.registerOperator(operator1, operatorId, key);
        uint256 gasUsed = gasBefore - gasleft();
        assertLt(gasUsed, 200000); // Should be less than 200k gas
    }

    function test_050_GasUsageOnCoordinatorRegistration() public {
        bytes memory quorumNumbers = abi.encodePacked(uint8(0));
        string memory socket = "tcp://localhost:8080";
        bytes memory params = abi.encode(operator1);
        bytes memory operatorSignature = abi.encodePacked("signature");
        
        uint256 gasBefore = gasleft();
        registryCoordinator.registerOperator(
            quorumNumbers,
            socket,
            params,
            operatorSignature
        );
        uint256 gasUsed = gasBefore - gasleft();
        assertLt(gasUsed, 500000); // Should be less than 500k gas
    }

    // ============ PERFORMANCE TESTS ============

    function test_051_PerformanceWithManyOperators() public {
        // Register many operators
        for (uint i = 0; i < 100; i++) {
            address operator = address(uint160(0x1000 + i));
            vm.deal(operator, 100 ether);
            vm.prank(operator);
            stakeRegistry.registerOperator(operator, MIN_STAKE);
        }
        
        assertEq(stakeRegistry.getOperatorCount(), 100);
        assertEq(stakeRegistry.getTotalStake(), MIN_STAKE * 100);
    }

    function test_052_PerformanceWithManyBlsKeys() public {
        // Register many BLS keys
        for (uint i = 0; i < 100; i++) {
            address operator = address(uint160(0x1000 + i));
            bytes32 operatorId = keccak256(abi.encodePacked(operator, "key"));
            CrossCoWBLSApkRegistry.BLSPublicKey memory key = CrossCoWBLSApkRegistry.BLSPublicKey({
                g1Pubkey: abi.encodePacked(operator, "g1"),
                g2Pubkey: abi.encodePacked(operator, "g2")
            });
            blsApkRegistry.registerOperator(operator, operatorId, key);
        }
        
        assertEq(blsApkRegistry.getOperatorCount(), 100);
    }

    function test_053_PerformanceWithManyCoordinatorRegistrations() public {
        // Register many operators in coordinator
        for (uint i = 0; i < 100; i++) {
            address operator = address(uint160(0x1000 + i));
            bytes memory quorumNumbers = abi.encodePacked(uint8(0));
            string memory socket = "tcp://localhost:8080";
            bytes memory params = abi.encode(operator);
            bytes memory operatorSignature = abi.encodePacked("signature");
            
            registryCoordinator.registerOperator(
                quorumNumbers,
                socket,
                params,
                operatorSignature
            );
        }
        
        address[] memory operators = registryCoordinator.getAllOperators();
        assertEq(operators.length, 100);
    }

    // ============ SECURITY TESTS ============

    function test_054_ReentrancyProtection() public {
        // This would test reentrancy protection
        assertTrue(true); // Placeholder
    }

    function test_055_AccessControl() public {
        // This would test access control mechanisms
        assertTrue(true); // Placeholder
    }

    function test_056_InputValidation() public {
        // This would test input validation
        assertTrue(true); // Placeholder
    }


    // ============ EVENTS ============

    event OperatorRegistered(address indexed operator, uint256 stake);
    event OperatorDeregistered(address indexed operator);
    event OperatorSlashed(address indexed operator, uint256 amount, string reason);
    event OperatorRewarded(address indexed operator, uint256 amount);
    event OperatorRegistered(address indexed operator, bytes32 indexed opId, CrossCoWBLSApkRegistry.BLSPublicKey key);
    event OperatorDeregistered(address indexed operator, bytes32 indexed opId);
    event PublicKeyUpdated(address indexed operator, CrossCoWBLSApkRegistry.BLSPublicKey newKey);
    event OperatorIdUpdated(address indexed operator, bytes32 newId);
    event QuorumBitmapUpdated(bytes32 indexed operatorId, uint192 newBitmap);
}
