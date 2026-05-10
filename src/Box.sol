// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Box is Ownable {
    uint256 public value;

    constructor(address _owner) Ownable(_owner) {}

    function store(uint256 _value) external onlyOwner {
        value = _value;
    }

    function retrieve() external view returns (uint256) {
        return value;
    }
}