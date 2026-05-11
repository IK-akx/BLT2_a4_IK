// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/GovernanceToken.sol";
import "../src/TokenVesting.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract GovernanceTokenTest is Test {
    using ECDSA for bytes32;

    GovernanceToken public token;
    TokenVesting public vesting;

    address public admin = address(1);
    address public team = address(2);
    address public treasury = address(3);
    address public airdrop = address(4);
    address public liquidity = address(5);

    address public voter1 = address(6);
    address public voter2 = address(7);
    address public delegatee = address(9);

    uint256 public constant TOTAL_SUPPLY = 1_000_000 * 10**18;
    uint256 public constant TEAM_AMOUNT = (TOTAL_SUPPLY * 4000) / 10000;
    uint256 public constant TREASURY_AMOUNT = (TOTAL_SUPPLY * 3000) / 10000;
    uint256 public constant AIRDROP_AMOUNT = (TOTAL_SUPPLY * 2000) / 10000;
    uint256 public constant LIQUIDITY_AMOUNT = TOTAL_SUPPLY - TEAM_AMOUNT - TREASURY_AMOUNT - AIRDROP_AMOUNT;

    function setUp() public {
        vm.startPrank(admin);

        token = new GovernanceToken(team, treasury, airdrop, liquidity);
        
        vesting = new TokenVesting(
            team,
            address(token),
            block.timestamp,  // начало сразу
            0,                // без клифа
            365 days          // 12 месяцев
        );
        
        vm.stopPrank();
        vm.prank(team);
        token.transfer(address(vesting), TEAM_AMOUNT);
    }

    function test_InitialDistribution() public {
        // Токены команды теперь в вестинге, а не у team
        assertEq(token.balanceOf(address(vesting)), TEAM_AMOUNT);
        assertEq(token.balanceOf(treasury), TREASURY_AMOUNT);
        assertEq(token.balanceOf(airdrop), AIRDROP_AMOUNT);
        assertEq(token.balanceOf(liquidity), LIQUIDITY_AMOUNT);
        assertEq(token.totalSupply(), TOTAL_SUPPLY);
    }

    function test_DistributionSumsTo100Percent() public {
        uint256 sum = token.balanceOf(address(vesting)) + 
                      token.balanceOf(treasury) + 
                      token.balanceOf(airdrop) + 
                      token.balanceOf(liquidity);
        assertEq(sum, TOTAL_SUPPLY);
    }

    function test_Delegation() public {
        vm.prank(airdrop);
        token.transfer(voter1, 1000 * 10**18);
        
        assertEq(token.getVotes(voter1), 0);
        
        vm.prank(voter1);
        token.delegate(voter1);
        
        vm.roll(block.number + 1);
        
        assertEq(token.getVotes(voter1), 1000 * 10**18);
    }

    function test_DelegateToAnotherAddress() public {
        vm.prank(airdrop);
        token.transfer(voter1, 500 * 10**18);
        
        vm.prank(airdrop);
        token.transfer(voter2, 300 * 10**18);
        
        vm.prank(voter1);
        token.delegate(delegatee);
        
        vm.prank(voter2);
        token.delegate(delegatee);
        
        vm.roll(block.number + 1);
        
        assertEq(token.getVotes(delegatee), 800 * 10**18);
        
        assertEq(token.getVotes(voter1), 0);
        assertEq(token.getVotes(voter2), 0);
    }

    function test_VotingPowerSnapshot() public {
        vm.prank(airdrop);
        token.transfer(voter1, 1000 * 10**18);
        
        vm.prank(voter1);
        token.delegate(voter1);
        
        vm.roll(block.number + 1);
        
        uint256 snapshotBlock = block.number - 1;
        uint256 pastVotes = token.getPastVotes(voter1, snapshotBlock);
        assertEq(pastVotes, 1000 * 10**18);
        
        vm.prank(airdrop);
        token.transfer(voter1, 100_000 * 10**18);
        
        vm.roll(block.number + 1);
        
        uint256 oldSnapshot = token.getPastVotes(voter1, snapshotBlock);
        assertEq(oldSnapshot, 1000 * 10**18);
        
        uint256 newSnapshot = token.getPastVotes(voter1, block.number - 1);
        assertEq(newSnapshot, 101_000 * 10**18);
    }

    function test_Permit() public {
        uint256 privateKey = 0xA11CE;
        address owner = vm.addr(privateKey);
        
        vm.prank(airdrop);
        token.transfer(owner, 1000 * 10**18);
        
        address spender = address(this);
        uint256 value = 100 * 10**18;
        uint256 deadline = block.timestamp + 1 days;
        uint256 nonce = token.nonces(owner);
        
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                value,
                nonce,
                deadline
            )
        );
        
        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        
        token.permit(owner, spender, value, deadline, v, r, s);
        
        assertEq(token.allowance(owner, spender), value);
    }

    function test_Vesting_NoTokensAtStart() public {
        vm.prank(team);
        vm.expectRevert("No tokens to release");
        vesting.release();
    }

    function test_Vesting_HalfAfterSixMonths() public {
        uint256 halfDuration = 365 days / 2;
        
        vm.warp(block.timestamp + halfDuration);
        vm.roll(block.number + 1);
        
        uint256 vested = vesting.vestedAmount();
        
        assertApproxEqRel(vested, TEAM_AMOUNT / 2, 0.0001e18);
        
        uint256 beforeBalance = token.balanceOf(team);
        vm.prank(team);
        vesting.release();
        uint256 afterBalance = token.balanceOf(team);
        
        assertGt(afterBalance, beforeBalance);
    }

    function test_Vesting_FullAfterTwelveMonths() public {
        vm.warp(block.timestamp + 366 days);
        vm.roll(block.number + 1);
        
        uint256 vested = vesting.vestedAmount();
        assertEq(vested, TEAM_AMOUNT);
        
        vm.prank(team);
        vesting.release();
        
        assertEq(token.balanceOf(team), TEAM_AMOUNT);
        assertEq(token.balanceOf(address(vesting)), 0);
    }

    function test_Vesting_MultipleReleases() public {
        uint256 quarterDuration = 365 days / 4;
        
        for (uint i = 1; i <= 4; i++) {
            vm.warp(block.timestamp + quarterDuration);
            vm.roll(block.number + 1);
            
            uint256 releasable = vesting.releasableAmount();
            if (releasable > 0) {
                vm.prank(team);
                vesting.release();
            }
        }
        
        assertApproxEqRel(token.balanceOf(team), TEAM_AMOUNT, 0.0001e18);
        assertLt(token.balanceOf(address(vesting)), 1 ether);
    }

    function test_Vesting_Revoke() public {
        vm.warp(block.timestamp + 90 days);
        vm.roll(block.number + 1);
        
        vm.prank(team);
        vesting.revoke();
        
        assertTrue(vesting.revoked());
        
        assertGt(token.balanceOf(team), 0);
    }

    function test_DistributionEvents() public {
        vm.startPrank(admin);
        
        address newTeam = address(10);
        address newTreasury = address(11);
        address newAirdrop = address(12);
        address newLiquidity = address(13);
        
        GovernanceToken newToken = new GovernanceToken(
            newTeam, newTreasury, newAirdrop, newLiquidity
        );
        
        uint256 teamAmount = (TOTAL_SUPPLY * 4000) / 10000;
        assertEq(newToken.balanceOf(newTeam), teamAmount);
        assertEq(newToken.balanceOf(newTreasury), (TOTAL_SUPPLY * 3000) / 10000);
        assertEq(newToken.balanceOf(newAirdrop), (TOTAL_SUPPLY * 2000) / 10000);
        assertEq(newToken.balanceOf(newLiquidity), 
            TOTAL_SUPPLY - teamAmount - (TOTAL_SUPPLY * 3000) / 10000 - (TOTAL_SUPPLY * 2000) / 10000);
        
        vm.stopPrank();
    }

    function test_ERC20_Transfer() public {
        uint256 amount = 100 * 10**18;
        
        vm.prank(airdrop);
        token.transfer(voter1, amount);
        
        assertEq(token.balanceOf(voter1), amount);
        assertEq(token.balanceOf(airdrop), AIRDROP_AMOUNT - amount);
    }

    function test_ERC20_ApproveAndTransferFrom() public {
        uint256 amount = 50 * 10**18;
        
        vm.prank(airdrop);
        token.approve(address(this), amount);
        
        token.transferFrom(airdrop, voter1, amount);
        
        assertEq(token.balanceOf(voter1), amount);
        assertEq(token.allowance(airdrop, address(this)), 0);
    }
}