// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IDEX {
    function flashLoan(uint256 amount, address receiverAddress) external;
}

contract FlashBorrower {
    IDEX public dex;
    IERC20 public token;

    constructor(address _dex, address _token) {
        dex = IDEX(_dex);
        token = IERC20(_token);
    }

    function executeFlashLoan(uint256 amount) external {
        dex.flashLoan(amount, address(this));
    }

    function executeOperation(uint256 amount, uint256 fee, address initiator) external returns (bool) {
        require(msg.sender == address(dex), "FlashBorrower: Caller is not DEX");
        
        // Do something with the loaned tokens here
        
        // Repay the loan
        uint256 amountToRepay = amount + fee;
        require(token.transfer(address(dex), amountToRepay), "FlashBorrower: Failed to repay");
        
        return true;
    }

    // Allow the contract to receive ETH
    receive() external payable {}
}