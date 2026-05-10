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

        address teamAddr = vm.envAddress("TEAM_ADDRESS");
        address treasuryAddr = vm.envAddress("TREASURY_ADDRESS");
        address airdropAddr = vm.envAddress("AIRDROP_ADDRESS");
        address liquidityAddr = vm.envAddress("LIQUIDITY_ADDRESS");

        uint256 minDelay = 2 days;

        console.log("=== Starting DAO Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Team beneficiary:", teamAddr);
        console.log("Min Timelock Delay:", minDelay, "seconds");

        vm.startBroadcast(deployerKey);

        // Step 1: Deploy TokenVesting first (empty)
        console.log("\n[1/7] Deploying TokenVesting...");
        TokenVesting vesting = new TokenVesting(teamAddr, address(0), block.timestamp, 0, 365 days);
        console.log("  Address:", address(vesting));

        // Step 2: Governance Token (mint team tokens to vesting contract)
        console.log("\n[2/7] Deploying GovernanceToken...");
        GovernanceToken token = new GovernanceToken(
            address(vesting),  // team tokens go to vesting
            treasuryAddr,
            airdropAddr,
            liquidityAddr
        );
        console.log("  Address:", address(token));
        console.log("  Total Supply:", token.totalSupply());

        // Step 3: Timelock Controller
        console.log("\n[3/7] Deploying TimelockController...");
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        TimelockController timelock = new TimelockController(minDelay, proposers, executors, deployer);
        console.log("  Address:", address(timelock));

        // Step 4: Governor
        console.log("\n[4/7] Deploying MyGovernor...");
        MyGovernor governor = new MyGovernor(IVotes(address(token)), timelock);
        console.log("  Address:", address(governor));

        // Step 5: Treasury + Box
        console.log("\n[5/7] Deploying Treasury and Box...");
        Treasury treasury = new Treasury(deployer);
        Box box = new Box(deployer);
        console.log("  Treasury:", address(treasury));
        console.log("  Box:", address(box));

        // Step 6: Setup permissions
        console.log("\n[6/7] Setting up permissions...");
        treasury.transferOwnership(address(timelock));
        box.transferOwnership(address(timelock));
        console.log("  Treasury owner -> Timelock");
        console.log("  Box owner -> Timelock");

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(governor));
        timelock.grantRole(cancellerRole, address(governor));
        console.log("  Governor -> Proposer + Executor + Canceller");

        timelock.renounceRole(proposerRole, deployer);
        timelock.renounceRole(executorRole, deployer);
        timelock.renounceRole(cancellerRole, deployer);
        console.log("  Deployer -> Roles renounced");

        vm.stopBroadcast();

        // Summary
        console.log("\n=== Deployment Summary ===");
        console.log('  "GovernanceToken": "', address(token), '",');
        console.log('  "TimelockController": "', address(timelock), '",');
        console.log('  "MyGovernor": "', address(governor), '",');
        console.log('  "Treasury": "', address(treasury), '",');
        console.log('  "Box": "', address(box), '",');
        console.log('  "TokenVesting": "', address(vesting), '"');
        console.log("\n  Team tokens vesting balance:", token.balanceOf(address(vesting)));
    }
}