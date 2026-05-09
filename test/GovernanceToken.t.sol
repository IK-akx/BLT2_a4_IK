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

        // 1. Сначала разворачиваем токен (team получает токены напрямую)
        token = new GovernanceToken(team, treasury, airdrop, liquidity);
        
        // 2. Создаем вестинг контракт БЕЗ начального баланса (пока он пустой)
        vesting = new TokenVesting(
            team,
            address(token),
            block.timestamp,  // начало сразу
            0,                // без клифа
            365 days          // 12 месяцев
        );
        
        // 3. Переводим токены команды с адреса team на вестинг контракт
        vm.stopPrank();
        vm.prank(team);
        token.transfer(address(vesting), TEAM_AMOUNT);
    }

    // ========== ТЕСТ 1: Правильное распределение токенов ==========
    function test_InitialDistribution() public {
        // Токены команды теперь в вестинге, а не у team
        assertEq(token.balanceOf(address(vesting)), TEAM_AMOUNT);
        assertEq(token.balanceOf(treasury), TREASURY_AMOUNT);
        assertEq(token.balanceOf(airdrop), AIRDROP_AMOUNT);
        assertEq(token.balanceOf(liquidity), LIQUIDITY_AMOUNT);
        assertEq(token.totalSupply(), TOTAL_SUPPLY);
    }

    // ========== ТЕСТ 2: Распределение в сумме = 100% ==========
    function test_DistributionSumsTo100Percent() public {
        uint256 sum = token.balanceOf(address(vesting)) + 
                      token.balanceOf(treasury) + 
                      token.balanceOf(airdrop) + 
                      token.balanceOf(liquidity);
        assertEq(sum, TOTAL_SUPPLY);
    }

    // ========== ТЕСТ 3: Делегирование голосов (себе) ==========
    function test_Delegation() public {
        // Даем voter1 токенов из airdrop
        vm.prank(airdrop);
        token.transfer(voter1, 1000 * 10**18);
        
        // Проверяем, что голосов пока нет (не делегированы)
        assertEq(token.getVotes(voter1), 0);
        
        // Делегируем себе
        vm.prank(voter1);
        token.delegate(voter1);
        
        // Перематываем блок для обновления снапшота
        vm.roll(block.number + 1);
        
        // Теперь есть голоса
        assertEq(token.getVotes(voter1), 1000 * 10**18);
    }

    // ========== ТЕСТ 4: Делегирование другому адресу ==========
    function test_DelegateToAnotherAddress() public {
        // Раздаем токены
        vm.prank(airdrop);
        token.transfer(voter1, 500 * 10**18);
        
        vm.prank(airdrop);
        token.transfer(voter2, 300 * 10**18);
        
        // voter1 делегирует delegatee
        vm.prank(voter1);
        token.delegate(delegatee);
        
        // voter2 делегирует delegatee
        vm.prank(voter2);
        token.delegate(delegatee);
        
        vm.roll(block.number + 1);
        
        // delegatee получает сумму голосов
        assertEq(token.getVotes(delegatee), 800 * 10**18);
        
        // У делегаторов голосов нет
        assertEq(token.getVotes(voter1), 0);
        assertEq(token.getVotes(voter2), 0);
    }

    // ========== ТЕСТ 5: Снапшот голосов (защита от flash loan) ==========
    function test_VotingPowerSnapshot() public {
        // Даем токены voter1
        vm.prank(airdrop);
        token.transfer(voter1, 1000 * 10**18);
        
        // Делегируем себе
        vm.prank(voter1);
        token.delegate(voter1);
        
        vm.roll(block.number + 1);
        
        uint256 snapshotBlock = block.number - 1;
        uint256 pastVotes = token.getPastVotes(voter1, snapshotBlock);
        assertEq(pastVotes, 1000 * 10**18);
        
        // Имитация flash loan - даем еще токенов
        vm.prank(airdrop);
        token.transfer(voter1, 100_000 * 10**18);
        
        vm.roll(block.number + 1);
        
        // На старом снапшоте голоса не изменились
        uint256 oldSnapshot = token.getPastVotes(voter1, snapshotBlock);
        assertEq(oldSnapshot, 1000 * 10**18);
        
        // На новом снапшоте голосов больше
        uint256 newSnapshot = token.getPastVotes(voter1, block.number - 1);
        assertEq(newSnapshot, 101_000 * 10**18);
    }

    // ========== ТЕСТ 6: Permit (газлесс подпись) ==========
    function test_Permit() public {
        uint256 privateKey = 0xA11CE;
        address owner = vm.addr(privateKey);
        
        // Даем токены owner
        vm.prank(airdrop);
        token.transfer(owner, 1000 * 10**18);
        
        address spender = address(this);
        uint256 value = 100 * 10**18;
        uint256 deadline = block.timestamp + 1 days;
        uint256 nonce = token.nonces(owner);
        
        // Строим permit хеш
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
        
        // Подписываем
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        
        // Выполняем permit
        token.permit(owner, spender, value, deadline, v, r, s);
        
        // Проверяем allowance
        assertEq(token.allowance(owner, spender), value);
    }

    // ========== ТЕСТ 7: Вестинг - нельзя получить в начале ==========
    function test_Vesting_NoTokensAtStart() public {
        // Пытаемся получить токены сразу
        vm.prank(team);
        vm.expectRevert("No tokens to release");
        vesting.release();
    }

    // ========== ТЕСТ 8: Вестинг - 50% после 6 месяцев (182.5 дня) ==========
    function test_Vesting_HalfAfterSixMonths() public {
        // Используем ровно половину срока (182.5 дня = 182 days + 12 hours)
        uint256 halfDuration = 365 days / 2;
        
        vm.warp(block.timestamp + halfDuration);
        vm.roll(block.number + 1);
        
        uint256 vested = vesting.vestedAmount();
        
        // Должно быть ровно 50% с допустимой погрешностью 0.01%
        assertApproxEqRel(vested, TEAM_AMOUNT / 2, 0.0001e18);
        
        // Получаем токены
        uint256 beforeBalance = token.balanceOf(team);
        vm.prank(team);
        vesting.release();
        uint256 afterBalance = token.balanceOf(team);
        
        assertGt(afterBalance, beforeBalance);
    }

    // ========== ТЕСТ 9: Вестинг - 100% после 12 месяцев ==========
    function test_Vesting_FullAfterTwelveMonths() public {
        // Перематываем на 12 месяцев + 1 день
        vm.warp(block.timestamp + 366 days);
        vm.roll(block.number + 1);
        
        uint256 vested = vesting.vestedAmount();
        assertEq(vested, TEAM_AMOUNT);
        
        // Получаем все токены
        vm.prank(team);
        vesting.release();
        
        assertEq(token.balanceOf(team), TEAM_AMOUNT);
        assertEq(token.balanceOf(address(vesting)), 0);
    }

    // ========== ТЕСТ 10: Вестинг - множественные release ==========
    function test_Vesting_MultipleReleases() public {
        // Получаем токены 4 раза с интервалом в 3 месяца (91.25 дня)
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
        
        // Проверяем, что получили почти всё (с погрешностью 0.01%)
        assertApproxEqRel(token.balanceOf(team), TEAM_AMOUNT, 0.0001e18);
        // На вестинге почти ничего не осталось
        assertLt(token.balanceOf(address(vesting)), 1 ether);
    }

    // ========== ТЕСТ 11: Вестинг - revoke ==========
    function test_Vesting_Revoke() public {
        // Перематываем на 3 месяца
        vm.warp(block.timestamp + 90 days);
        vm.roll(block.number + 1);
        
        // Отзываем вестинг (team = owner)
        vm.prank(team);
        vesting.revoke();
        
        assertTrue(vesting.revoked());
        
        // Неразблокированные токены вернулись
        assertGt(token.balanceOf(team), 0);
    }

    // ========== ТЕСТ 12: Проверка event'ов распределения ==========
    function test_DistributionEvents() public {
        vm.startPrank(admin);
        
        address newTeam = address(10);
        address newTreasury = address(11);
        address newAirdrop = address(12);
        address newLiquidity = address(13);
        
        GovernanceToken newToken = new GovernanceToken(
            newTeam, newTreasury, newAirdrop, newLiquidity
        );
        
        // Проверяем балансы
        uint256 teamAmount = (TOTAL_SUPPLY * 4000) / 10000;
        assertEq(newToken.balanceOf(newTeam), teamAmount);
        assertEq(newToken.balanceOf(newTreasury), (TOTAL_SUPPLY * 3000) / 10000);
        assertEq(newToken.balanceOf(newAirdrop), (TOTAL_SUPPLY * 2000) / 10000);
        assertEq(newToken.balanceOf(newLiquidity), 
            TOTAL_SUPPLY - teamAmount - (TOTAL_SUPPLY * 3000) / 10000 - (TOTAL_SUPPLY * 2000) / 10000);
        
        vm.stopPrank();
    }

    // ========== ТЕСТ 13: ERC20 стандартные функции ==========
    function test_ERC20_Transfer() public {
        uint256 amount = 100 * 10**18;
        
        vm.prank(airdrop);
        token.transfer(voter1, amount);
        
        assertEq(token.balanceOf(voter1), amount);
        assertEq(token.balanceOf(airdrop), AIRDROP_AMOUNT - amount);
    }

    // ========== ТЕСТ 14: ERC20_Approve_TransferFrom ==========
    function test_ERC20_ApproveAndTransferFrom() public {
        uint256 amount = 50 * 10**18;
        
        vm.prank(airdrop);
        token.approve(address(this), amount);
        
        token.transferFrom(airdrop, voter1, amount);
        
        assertEq(token.balanceOf(voter1), amount);
        assertEq(token.allowance(airdrop, address(this)), 0);
    }
}