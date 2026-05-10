// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Treasury is Ownable {
    using SafeERC20 for IERC20;

    constructor(address _owner) Ownable(_owner) {}

    receive() external payable {}

    function withdrawERC20(address _token, address _to, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(_to, _amount);
    }

    function withdrawETH(address payable _to, uint256 _amount) external onlyOwner {
        _to.transfer(_amount);
    }
}