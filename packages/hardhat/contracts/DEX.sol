// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract DEX is ReentrancyGuard {
    /* ========== GLOBAL VARIABLES ========== */

    IERC20 public token;
    uint256 public totalLiquidity;
    mapping(address => uint256) public liquidity;

    /* ========== EVENTS ========== */

    event EthToTokenSwap(address swapper, uint256 tokenOutput, uint256 ethInput);
    event TokenToEthSwap(address swapper, uint256 tokensInput, uint256 ethOutput);
    event LiquidityProvided(address liquidityProvider, uint256 liquidityMinted, uint256 ethInput, uint256 tokensInput);
    event LiquidityRemoved(address liquidityRemover, uint256 liquidityWithdrawn, uint256 tokensOutput, uint256 ethOutput);

    /* ========== CONSTRUCTOR ========== */

    constructor(address token_addr) {
        token = IERC20(token_addr);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function init(uint256 tokens) public payable returns (uint256) {
        require(totalLiquidity == 0, "DEX: already initialized");
        require(tokens > 0 && msg.value > 0, "DEX: zero amounts not allowed");
        
        totalLiquidity = msg.value;
        liquidity[msg.sender] = totalLiquidity;
        
        require(token.transferFrom(msg.sender, address(this), tokens), "DEX: transfer failed");
        
        return totalLiquidity;
    }

    function price(uint256 xInput, uint256 xReserves, uint256 yReserves) public pure returns (uint256 yOutput) {
        uint256 xInputWithFee = xInput * 997;
        uint256 numerator = xInputWithFee * yReserves;
        uint256 denominator = (xReserves * 1000) + xInputWithFee;
        return numerator / denominator;
    }

    function getLiquidity(address lp) public view returns (uint256) {
        return liquidity[lp];
    }

    function ethToToken() public payable nonReentrant returns (uint256 tokenOutput) {
        require(msg.value > 0, "DEX: zero amounts not allowed");
        uint256 ethReserve = address(this).balance - msg.value;
        uint256 tokenReserve = token.balanceOf(address(this));
        tokenOutput = price(msg.value, ethReserve, tokenReserve);

        require(token.transfer(msg.sender, tokenOutput), "DEX: transfer failed");
        
        emit EthToTokenSwap(msg.sender, tokenOutput, msg.value);
        return tokenOutput;
    }

    function tokenToEth(uint256 tokenInput) public nonReentrant returns (uint256 ethOutput) {
        require(tokenInput > 0, "DEX: zero amounts not allowed");
        uint256 tokenReserve = token.balanceOf(address(this));
        uint256 ethReserve = address(this).balance;
        ethOutput = price(tokenInput, tokenReserve, ethReserve);

        require(token.transferFrom(msg.sender, address(this), tokenInput), "DEX: transfer failed");
        (bool sent, ) = msg.sender.call{value: ethOutput}("");
        require(sent, "DEX: ETH transfer failed");
        
        emit TokenToEthSwap(msg.sender, tokenInput, ethOutput);
        return ethOutput;
    }

    function deposit() public payable nonReentrant returns (uint256 tokensDeposited) {
        require(msg.value > 0, "DEX: zero amounts not allowed");
        uint256 ethReserve = address(this).balance - msg.value;
        uint256 tokenReserve = token.balanceOf(address(this));
        uint256 tokenDeposit;
        
        if (totalLiquidity > 0) {
            tokenDeposit = (msg.value * tokenReserve) / ethReserve;
        } else {
            tokenDeposit = msg.value;
        }
        
        uint256 liquidityMinted = (msg.value * totalLiquidity) / ethReserve;
        liquidity[msg.sender] += liquidityMinted;
        totalLiquidity += liquidityMinted;

        require(token.transferFrom(msg.sender, address(this), tokenDeposit), "DEX: transfer failed");
        
        emit LiquidityProvided(msg.sender, liquidityMinted, msg.value, tokenDeposit);
        return tokenDeposit;
    }

    function withdraw(uint256 amount) public nonReentrant returns (uint256 eth_amount, uint256 token_amount) {
        require(liquidity[msg.sender] >= amount, "DEX: insufficient liquidity");
        uint256 ethReserve = address(this).balance;
        uint256 tokenReserve = token.balanceOf(address(this));
        
        eth_amount = (amount * ethReserve) / totalLiquidity;
        token_amount = (amount * tokenReserve) / totalLiquidity;

        liquidity[msg.sender] -= amount;
        totalLiquidity -= amount;

        (bool sent, ) = msg.sender.call{value: eth_amount}("");
        require(sent, "DEX: ETH transfer failed");
        require(token.transfer(msg.sender, token_amount), "DEX: token transfer failed");

        emit LiquidityRemoved(msg.sender, amount, token_amount, eth_amount);
        return (eth_amount, token_amount);
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}
}