// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFlashLoanReceiver {
    function executeOperation(uint256 amount, uint256 fee, address initiator) external returns (bool);
}