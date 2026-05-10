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

contract MyGovernorTest is Test {
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
    address public voter2 = makeAddr("voter2");
    address public voter3 = makeAddr("voter3");
    address public delegatee = makeAddr("delegatee");

    uint256 public constant TOTAL_SUPPLY = 1_000_000 * 10**18;
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

        vm.prank(treasuryAddr);
        token.transfer(address(treasury), 300_000 * 10**18);

        vm.startPrank(airdrop);
        token.transfer(voter1, 60_000 * 10**18);
        token.transfer(voter2, 60_000 * 10**18);
        token.transfer(voter3, 50_000 * 10**18);
        vm.stopPrank();

        vm.prank(voter1);
        token.delegate(voter1);
        vm.prank(voter2);
        token.delegate(voter2);
        vm.prank(voter3);
        token.delegate(voter3);

        vm.roll(block.number + 1);
    }

    function _createProposal(address target, bytes memory data) internal returns (uint256 proposalId, bytes32 descriptionHash) {
        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = data;

        string memory description = "Test proposal";
        descriptionHash = keccak256(abi.encodePacked(description));

        vm.prank(voter1);
        proposalId = governor.propose(targets, values, calldatas, description);
    }

    function _voteAndPass(uint256 proposalId) internal {
        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(voter1);
        governor.castVote(proposalId, 1);
        vm.prank(voter3);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + governor.votingPeriod() + 1);
    }

    function test_Deploy_GovernorParameters() public view {
        assertEq(governor.votingDelay(), 7200);
        assertEq(governor.votingPeriod(), 50400);
        assertEq(governor.proposalThreshold(), TOTAL_SUPPLY / 100);
    }

    function test_Timelock_Delay() public view {
        assertEq(timelock.getMinDelay(), MIN_DELAY);
    }

    function test_FullLifecycle_Transfer() public {
        uint256 amount = 100 * 10**18;
        bytes memory data = abi.encodeWithSignature(
            "withdrawERC20(address,address,uint256)",
            address(token), voter2, amount
        );

        (uint256 proposalId, bytes32 descHash) = _createProposal(address(treasury), data);
        _voteAndPass(proposalId);

        address[] memory targets = new address[](1);
        targets[0] = address(treasury);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = data;

        governor.queue(targets, values, calldatas, descHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + 1);

        governor.execute(targets, values, calldatas, descHash);

        assertEq(token.balanceOf(voter2), 60_000 * 10**18 + amount);
    }

    function test_FullLifecycle_ChangeBox() public {
        bytes memory data = abi.encodeWithSignature("store(uint256)", 42);
        (uint256 proposalId, bytes32 descHash) = _createProposal(address(box), data);
        _voteAndPass(proposalId);

        address[] memory targets = new address[](1);
        targets[0] = address(box);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = data;

        governor.queue(targets, values, calldatas, descHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + 1);

        governor.execute(targets, values, calldatas, descHash);

        assertEq(box.value(), 42);
    }

    function test_ProposalStates() public {
        bytes memory data = abi.encodeWithSignature("store(uint256)", 1);
        (uint256 proposalId, ) = _createProposal(address(box), data);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));

        vm.roll(block.number + governor.votingDelay() + 1);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));

        vm.prank(voter1);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + governor.votingPeriod() + 1);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));
    }

    function test_VoteTypes() public {
        bytes memory data = abi.encodeWithSignature("store(uint256)", 1);
        (uint256 proposalId, ) = _createProposal(address(box), data);

        vm.roll(block.number + governor.votingDelay() + 1);

        vm.prank(voter1);
        governor.castVote(proposalId, 1);
        vm.prank(voter2);
        governor.castVote(proposalId, 0);
        vm.prank(voter3);
        governor.castVote(proposalId, 2);

        vm.roll(block.number + governor.votingPeriod() + 1);

        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        assertGt(forVotes, 0);
        assertGt(againstVotes, 0);
        assertGt(abstainVotes, 0);
    }

    function test_QuorumMet() public {
        bytes memory data = abi.encodeWithSignature("store(uint256)", 1);
        (uint256 proposalId, ) = _createProposal(address(box), data);

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(voter1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + governor.votingPeriod() + 1);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));
    }

    function test_ProposalDefeated_NoQuorum() public {
        address tinyVoter = makeAddr("tinyVoter");
        vm.prank(airdrop);
        token.transfer(tinyVoter, 30_000 * 10**18); // 3% > 1% threshold
        vm.prank(tinyVoter);
        token.delegate(tinyVoter);
        vm.roll(block.number + 1);

        vm.prank(tinyVoter);
        uint256 pid = governor.propose(
            new address[](1),
            new uint256[](1),
            new bytes[](1),
            "No quorum"
        );

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(tinyVoter);
        governor.castVote(pid, 1);
        vm.roll(block.number + governor.votingPeriod() + 1);

        // 3% < 4% quorum => defeated
        assertEq(uint256(governor.state(pid)), uint256(IGovernor.ProposalState.Defeated));
    }

    function test_VoteDelegation() public {
        vm.prank(voter2);
        token.delegate(delegatee);
        vm.roll(block.number + 1);

        bytes memory data = abi.encodeWithSignature("store(uint256)", 7);
       (uint256 proposalId, ) = _createProposal(address(box), data);

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(delegatee);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + governor.votingPeriod() + 1);

        (uint256 againstVotes, uint256 forVotes,) = governor.proposalVotes(proposalId);
        assertGt(forVotes, 0);
    }

    function test_CannotPropose_BelowThreshold() public {
        address poorVoter = makeAddr("poorVoter");
        vm.prank(airdrop);
        token.transfer(poorVoter, 1000 * 10**18);
        vm.prank(poorVoter);
        token.delegate(poorVoter);
        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        targets[0] = address(box);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("store(uint256)", 1);

        vm.prank(poorVoter);
        vm.expectRevert();
        governor.propose(targets, values, calldatas, "Should fail");
    }

    function test_CannotExecute_BeforeDelay() public {
        bytes memory data = abi.encodeWithSignature("store(uint256)", 1);
        (uint256 proposalId, bytes32 descHash) = _createProposal(address(box), data);
        _voteAndPass(proposalId);

        address[] memory targets = new address[](1);
        targets[0] = address(box);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = data;

        governor.queue(targets, values, calldatas, descHash);

        vm.expectRevert();
        governor.execute(targets, values, calldatas, descHash);
    }
    
    function test_TreasuryOwnedByTimelock() public view {
        assertEq(treasury.owner(), address(timelock));
        assertEq(box.owner(), address(timelock));
    }

    function test_CannotWithdraw_Directly() public {
        vm.prank(voter2);
        vm.expectRevert();
        treasury.withdrawERC20(address(token), voter2, 100 * 10**18);
    }

    function test_OnlyGovernorCanPropose() public view {
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)));
        assertFalse(timelock.hasRole(timelock.PROPOSER_ROLE(), address(admin)));
    }

    // for task 3
    function test_FullLifecycle_SendETH() public {
        // Fund treasury with ETH
        vm.deal(address(treasury), 10 ether);
        assertEq(address(treasury).balance, 10 ether);

        bytes memory data = abi.encodeWithSignature("withdrawETH(address,uint256)", voter2, 1 ether);
        (uint256 proposalId, bytes32 descHash) = _createProposal(address(treasury), data);
        _voteAndPass(proposalId);

        address[] memory targets = new address[](1);
        targets[0] = address(treasury);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = data;

        governor.queue(targets, values, calldatas, descHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + 1);

        uint256 balanceBefore = voter2.balance;
        governor.execute(targets, values, calldatas, descHash);

        assertEq(voter2.balance, balanceBefore + 1 ether);
        assertEq(address(treasury).balance, 9 ether);
    }
}