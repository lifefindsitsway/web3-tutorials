// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract Logic {
    uint256 public value;

    event ValueChanged(address indexed caller, uint256 indexed newValue);

    function setValue(uint256 newValue) external returns (bool) {
        value = newValue;
        emit ValueChanged(msg.sender, value);
        return true;
    }
}