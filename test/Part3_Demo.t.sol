// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/GovernanceToken.sol";
import "../src/Treasury.sol";
import "../src/Box.sol";
import "../src/MyGovernor.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/governance/utils/IVotes.sol";
import "@openzeppelin/contracts/governance/IGovernor.sol";

contract Part3Demo is Test {
    GovernanceToken public token;
    MyGovernor public governor;
    TimelockController public timelock;
    Treasury public treasury;
    Box public box;

    address public admin = makeAddr("admin");
    address public team = makeAddr("team");
    address public treasuryAddr = makeAddr("treasuryAddr");
    address public airdrop = makeAddr("airdrop");
    address public liquidity = makeAddr("liquidity");
    address public voter1 = makeAddr("voter1");

    uint256 public constant MIN_DELAY = 2 days;

    function setUp() public {
        vm.prank(admin);
        token = new GovernanceToken(team, treasuryAddr, airdrop, liquidity);

        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);

        vm.prank(admin);
        timelock = new TimelockController(MIN_DELAY, proposers, executors, admin);

        vm.prank(admin);
        governor = new MyGovernor(IVotes(address(token)), timelock);

        vm.prank(admin);
        treasury = new Treasury(admin);
        vm.prank(admin);
        box = new Box(admin);

        vm.prank(admin);
        treasury.transferOwnership(address(timelock));
        vm.prank(admin);
        box.transferOwnership(address(timelock));

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();

        vm.startPrank(admin);
        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(governor));
        timelock.grantRole(cancellerRole, address(governor));
        timelock.renounceRole(proposerRole, admin);
        timelock.renounceRole(executorRole, admin);
        timelock.renounceRole(cancellerRole, admin);
        vm.stopPrank();

        // Give voter1 enough tokens to propose
        vm.prank(treasuryAddr);
        token.transfer(address(treasury), 300_000 * 10**18);

        vm.prank(airdrop);
        token.transfer(voter1, 50_000 * 10**18);

        vm.prank(voter1);
        token.delegate(voter1);
        vm.roll(block.number + 1);
    }

    function test_EndToEnd_BoxStore42() public {
        console.log("\n=== STEP 1: Check Box value before ===");
        console.log("Box.value =", box.value());
        assertEq(box.value(), 0);

        console.log("\n=== STEP 2: Create proposal to store 42 ===");
        bytes memory data = abi.encodeWithSignature("store(uint256)", 42);
        
        address[] memory targets = new address[](1);
        targets[0] = address(box);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = data;
        string memory description = "Set Box value to 42";

        vm.prank(voter1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        console.log("Proposal ID:", proposalId);
        console.log("Proposal state: Pending");

        console.log("\n=== STEP 3: Voting delay passes, proposal active ===");
        vm.roll(block.number + governor.votingDelay() + 1);
        console.log("Current block:", block.number);
        console.log("Proposal state: Active");

        console.log("\n=== STEP 4: Cast vote FOR ===");
        vm.prank(voter1);
        governor.castVote(proposalId, 1);
        console.log("Voter1 voted FOR with", token.getPastVotes(voter1, block.number - 1), "votes");

        console.log("\n=== STEP 5: Voting period ends ===");
        vm.roll(block.number + governor.votingPeriod() + 1);
        console.log("Proposal state: Succeeded");
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        console.log("\n=== STEP 6: Queue proposal in Timelock ===");
        bytes32 descHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, calldatas, descHash);
        console.log("Proposal queued. Must wait", MIN_DELAY, "seconds");

        console.log("\n=== STEP 7: Wait for timelock delay ===");
        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + 1);
        console.log("Delay passed. Ready to execute.");

        console.log("\n=== STEP 8: Execute proposal ===");
        governor.execute(targets, values, calldatas, descHash);
        console.log("Proposal executed!");

        console.log("\n=== STEP 9: Verify Box value changed ===");
        console.log("Box.value =", box.value());
        assertEq(box.value(), 42);
        console.log("SUCCESS: Box.value is now 42!");
    }

    function test_EndToEnd_TreasuryTransfer() public {
        uint256 amount = 100 * 10**18;

        console.log("\n=== STEP 1: Check treasury balance ===");
        uint256 treasuryBalance = token.balanceOf(address(treasury));
        console.log("Treasury balance:", treasuryBalance);

        console.log("\n=== STEP 2: Create proposal to transfer tokens ===");
        bytes memory data = abi.encodeWithSignature(
            "withdrawERC20(address,address,uint256)",
            address(token), voter1, amount
        );

        address[] memory targets = new address[](1);
        targets[0] = address(treasury);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = data;
        string memory description = "Transfer tokens to voter1";

        vm.prank(voter1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        console.log("Proposal ID:", proposalId);

        console.log("\n=== STEP 3: Vote and pass ===");
        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(voter1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + governor.votingPeriod() + 1);

        console.log("\n=== STEP 4: Queue and execute after delay ===");
        bytes32 descHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, calldatas, descHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + 1);

        uint256 balanceBefore = token.balanceOf(voter1);
        governor.execute(targets, values, calldatas, descHash);

        console.log("\n=== STEP 5: Verify transfer ===");
        console.log("Voter1 balance before:", balanceBefore);
        console.log("Voter1 balance after:", token.balanceOf(voter1));
        assertEq(token.balanceOf(voter1), balanceBefore + amount);
        console.log("SUCCESS: Tokens transferred!");
    }
}