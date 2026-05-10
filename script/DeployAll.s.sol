// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/GovernanceToken.sol";
import "../src/TokenVesting.sol";
import "../src/Treasury.sol";
import "../src/Box.sol";
import "../src/MyGovernor.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/governance/utils/IVotes.sol";

contract DeployAll is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        // Адреса из .env
        address teamAddr = vm.envAddress("TEAM_ADDRESS");
        address treasuryAddr = vm.envAddress("TREASURY_ADDRESS");
        address airdropAddr = vm.envAddress("AIRDROP_ADDRESS");
        address liquidityAddr = vm.envAddress("LIQUIDITY_ADDRESS");

        uint256 minDelay = 2 days;

        vm.startBroadcast(deployerKey);

        // 1. Token
        GovernanceToken token = new GovernanceToken(teamAddr, treasuryAddr, airdropAddr, liquidityAddr);
        console.log("GovernanceToken:", address(token));

        // 2. Timelock
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        TimelockController timelock = new TimelockController(minDelay, proposers, executors, deployer);
        console.log("Timelock:", address(timelock));

        // 3. Governor
        MyGovernor governor = new MyGovernor(IVotes(address(token)), timelock);
        console.log("MyGovernor:", address(governor));

        // 4. Treasury + Box
        Treasury treasury = new Treasury(deployer);
        Box box = new Box(deployer);
        console.log("Treasury:", address(treasury));
        console.log("Box:", address(box));

        // 5. Transfer ownership to timelock
        treasury.transferOwnership(address(timelock));
        box.transferOwnership(address(timelock));

        // 6. Grant roles to governor
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(governor));
        timelock.grantRole(cancellerRole, address(governor));
        timelock.renounceRole(proposerRole, deployer);
        timelock.renounceRole(executorRole, deployer);
        timelock.renounceRole(cancellerRole, deployer);

        // 7. TokenVesting for team
        TokenVesting vesting = new TokenVesting(teamAddr, address(token), block.timestamp, 0, 365 days);
        console.log("TokenVesting:", address(vesting));

        vm.stopBroadcast();

        console.log("\n=== Deployed Addresses ===");
        console.log("Token:", address(token));
        console.log("Timelock:", address(timelock));
        console.log("Governor:", address(governor));
        console.log("Treasury:", address(treasury));
        console.log("Box:", address(box));
        console.log("Vesting:", address(vesting));
    }
}