// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenVesting is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    address public immutable beneficiary;
    uint256 public immutable start;
    uint256 public immutable duration;
    uint256 public immutable cliff;

    uint256 public released;
    bool public revoked;

    event TokensReleased(address indexed beneficiary, uint256 amount);
    event VestingRevoked(address indexed owner, uint256 unreleasedAmount);

    modifier notRevoked() {
        require(!revoked, "Vesting has been revoked");
        _;
    }

    constructor(
        address _beneficiary,
        address _token,
        uint256 _startTimestamp,
        uint256 _cliffDuration,
        uint256 _vestingDuration
    ) Ownable(_beneficiary) {
        require(_beneficiary != address(0), "Beneficiary cannot be zero address");
        require(_token != address(0), "Token cannot be zero address");
        require(_vestingDuration > 0, "Duration must be > 0");
        require(_startTimestamp >= block.timestamp, "Start must be >= current time");

        token = IERC20(_token);
        beneficiary = _beneficiary;
        start = _startTimestamp;
        cliff = _startTimestamp + _cliffDuration;
        duration = _vestingDuration;
        
        // Убираем проверку баланса - токены могут быть переведены позже
    }

    // Функция для инициализации токенов (вызывается один раз)
    function initializeTokens() external {
        require(token.balanceOf(address(this)) > 0, "No tokens allocated to vesting");
    }

    function totalAllocation() public view returns (uint256) {
        return token.balanceOf(address(this)) + released;
    }

    function vestedAmount() public view returns (uint256) {
        uint256 currentTime = block.timestamp;
        uint256 total = totalAllocation();

        if (currentTime < cliff) {
            return 0;
        } else if (currentTime >= start + duration || revoked) {
            return total;
        } else {
            return (total * (currentTime - start)) / duration;
        }
    }

    function releasableAmount() public view returns (uint256) {
        return vestedAmount() - released;
    }

    function release() external notRevoked {
        uint256 amount = releasableAmount();
        require(amount > 0, "No tokens to release");

        released += amount;
        token.safeTransfer(beneficiary, amount);

        emit TokensReleased(beneficiary, amount);
    }

    function revoke() external onlyOwner notRevoked {
        revoked = true;

        uint256 unreleased = totalAllocation() - released;
        if (unreleased > 0) {
            token.safeTransfer(owner(), unreleased);
        }

        emit VestingRevoked(owner(), unreleased);
    }

    function getBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }
}