// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Treasury is Ownable {
    using SafeERC20 for IERC20;

    event ERC20Withdrawn(address indexed token, address indexed to, uint256 amount);
    event ETHWithdrawn(address indexed to, uint256 amount);

    constructor(address initialOwner) Ownable(initialOwner) {}

    receive() external payable {}

    function withdrawERC20(address tokenAddr, address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Treasury: zero address");
        IERC20(tokenAddr).safeTransfer(to, amount);
        emit ERC20Withdrawn(tokenAddr, to, amount);
    }

    function withdrawETH(address payable to, uint256 amount) external onlyOwner {
        require(to != address(0), "Treasury: zero address");
        to.transfer(amount);
        emit ETHWithdrawn(to, amount);
    }
}