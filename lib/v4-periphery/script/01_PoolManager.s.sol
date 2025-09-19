// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {PoolManager} from "@uniswap/v4-core/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";

import "forge-std/console2.sol";

contract DeployPoolManager is Script {
    function setUp() public {}

    function run() public returns (IPoolManager manager) {
        vm.startBroadcast();

        manager = new PoolManager(address(this));
        console2.log("PoolManager", address(manager));

        vm.stopBroadcast();
    }
}
