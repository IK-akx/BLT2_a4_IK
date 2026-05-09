// script/DeployPart1.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/GovernanceToken.sol";
import "../src/TokenVesting.sol";

contract DeployPart1 is Script {
    function run() external {
        // Читаем из .env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        address teamAddress = vm.envAddress("TEAM_ADDRESS");
        address treasuryAddress = vm.envAddress("TREASURY_ADDRESS");
        address airdropAddress = vm.envAddress("AIRDROP_ADDRESS");
        address liquidityAddress = vm.envAddress("LIQUIDITY_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Team address:", teamAddress);
        console.log("Treasury address:", treasuryAddress);
        
        // 1. Разворачиваем GovernanceToken
        GovernanceToken token = new GovernanceToken(
            teamAddress,
            treasuryAddress,
            airdropAddress,
            liquidityAddress
        );

        console.log("\n=== GovernanceToken deployed ===");
        console.log("Address:", address(token));
        console.log("Total supply:", token.totalSupply());

        // 2. Разворачиваем TokenVesting
        TokenVesting vesting = new TokenVesting(
            teamAddress,
            address(token),
            block.timestamp,
            0,           // без клифа
            365 days     // 12 месяцев
        );

        console.log("\n=== TokenVesting deployed ===");
        console.log("Address:", address(vesting));
        console.log("Beneficiary:", teamAddress);
        console.log("Total allocation:", vesting.totalAllocation());

        vm.stopBroadcast();

        // Вывод распределения
        console.log("\n=== Token Distribution ===");
        console.log("Team (direct):", token.balanceOf(teamAddress));
        console.log("Treasury:", token.balanceOf(treasuryAddress));
        console.log("Airdrop:", token.balanceOf(airdropAddress));
        console.log("Liquidity:", token.balanceOf(liquidityAddress));
    }
}