// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10**18);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock Pool Manager
contract MockPoolManager {
    function getSlot0(bytes32) external pure returns (uint160, int24, uint24, uint24, uint24, uint24, uint128) {
        return (0, 0, 0, 0, 0, 0, 0);
    }
}

// Mock Across Hub Pool
contract MockAcrossHubPool {
    function deposit(
        address recipient,
        address originToken,
        uint256 amount,
        uint256 destinationChainId,
        uint64 relayerFeePct,
        uint32 quoteTimestamp,
        bytes memory message,
        uint256 maxCount
    ) external payable returns (uint32) {
        return 1; // Mock deposit ID
    }
}
