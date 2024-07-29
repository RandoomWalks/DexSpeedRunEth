// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract DEX is ReentrancyGuard, Ownable {
	using SafeMath for uint256;

	IERC20 public token;
	uint256 public totalLiquidity;
	mapping(address => uint256) public liquidity;

	uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;
	uint256 public constant FEE_PERCENT = 3; // 0.3% fee
	uint256 public constant FEE_DENOMINATOR = 1000;

	bool public emergencyStop;

	event EthToTokenSwap(
		address indexed swapper,
		uint256 tokenOutput,
		uint256 ethInput
	);
	event TokenToEthSwap(
		address indexed swapper,
		uint256 tokensInput,
		uint256 ethOutput
	);
	event LiquidityProvided(
		address indexed liquidityProvider,
		uint256 liquidityMinted,
		uint256 ethInput,
		uint256 tokensInput
	);
	event LiquidityRemoved(
		address indexed liquidityRemover,
		uint256 liquidityWithdrawn,
		uint256 tokensOutput,
		uint256 ethOutput
	);
	event EmergencyStopSet(bool stopped);

	modifier notStopped() {
		require(!emergencyStop, "DEX: Emergency stop is active");
		_;
	}

	constructor(address token_addr) {
		token = IERC20(token_addr);
	}

	function setEmergencyStop(bool _stopped) external onlyOwner {
		emergencyStop = _stopped;
		emit EmergencyStopSet(_stopped);
	}

	function init(uint256 tokens) external payable returns (uint256) {
		require(totalLiquidity == 0, "DEX: already initialized");
		require(
			tokens > MINIMUM_LIQUIDITY && msg.value > MINIMUM_LIQUIDITY,
			"DEX: insufficient initial liquidity"
		);

		totalLiquidity = msg.value;
		liquidity[msg.sender] = totalLiquidity;

		require(
			token.transferFrom(msg.sender, address(this), tokens),
			"DEX: transfer failed"
		);

		return totalLiquidity;
	}

	// function price(uint256 inputAmount, uint256 inputReserve, uint256 outputReserve) public pure returns (uint256) {
	//     require(inputReserve > 0 && outputReserve > 0, "DEX: invalid reserves");
	//     uint256 inputAmountWithFee = inputAmount.mul(FEE_DENOMINATOR.sub(FEE_PERCENT));
	//     uint256 numerator = inputAmountWithFee.mul(outputReserve);
	//     uint256 denominator = inputReserve.mul(FEE_DENOMINATOR).add(inputAmountWithFee);
	//     return numerator.div(denominator);
	// }

	// In the DEX contract
	function price(
		uint256 inputAmount,
		uint256 inputReserve,
		uint256 outputReserve
	) public pure returns (uint256) {
		require(inputReserve > 0 && outputReserve > 0, "DEX: invalid reserves");
		uint256 inputAmountWithFee = inputAmount.mul(997);
		uint256 numerator = inputAmountWithFee.mul(outputReserve);
		uint256 denominator = inputReserve.mul(1000).add(inputAmountWithFee);
		return numerator.div(denominator);
	}

	function getLiquidity(address lp) external view returns (uint256) {
		return liquidity[lp];
	}

	function ethToToken()
		external
		payable
		nonReentrant
		notStopped
		returns (uint256 tokenOutput)
	{
		require(msg.value > 0, "DEX: zero amounts not allowed");
		uint256 ethReserve = address(this).balance.sub(msg.value);
		uint256 tokenReserve = token.balanceOf(address(this));
		tokenOutput = price(msg.value, ethReserve, tokenReserve);

		require(tokenOutput > 0, "DEX: insufficient output amount");
		require(
			tokenOutput <= token.balanceOf(address(this)),
			"DEX: insufficient liquidity"
		);

		require(
			token.transfer(msg.sender, tokenOutput),
			"DEX: transfer failed"
		);

		emit EthToTokenSwap(msg.sender, tokenOutput, msg.value);
		return tokenOutput;
	}

	function tokenToEth(
		uint256 tokenInput
	) external nonReentrant notStopped returns (uint256 ethOutput) {
		require(tokenInput > 0, "DEX: zero amounts not allowed");
		uint256 tokenReserve = token.balanceOf(address(this));
		uint256 ethReserve = address(this).balance;
		ethOutput = price(tokenInput, tokenReserve, ethReserve);

		require(ethOutput > 0, "DEX: insufficient output amount");
		require(
			ethOutput <= address(this).balance,
			"DEX: insufficient liquidity"
		);

		require(
			token.transferFrom(msg.sender, address(this), tokenInput),
			"DEX: transfer failed"
		);
		(bool sent, ) = msg.sender.call{ value: ethOutput }("");
		require(sent, "DEX: ETH transfer failed");

		emit TokenToEthSwap(msg.sender, tokenInput, ethOutput);
		return ethOutput;
	}

	function deposit()
		external
		payable
		nonReentrant
		notStopped
		returns (uint256 tokensDeposited)
	{
		require(msg.value > 0, "DEX: zero amounts not allowed");
		uint256 ethReserve = address(this).balance.sub(msg.value);
		uint256 tokenReserve = token.balanceOf(address(this));
		uint256 tokenDeposit;

		if (totalLiquidity > 0) {
			tokenDeposit = msg.value.mul(tokenReserve).div(ethReserve);
		} else {
			tokenDeposit = msg.value;
		}

		uint256 liquidityMinted = msg.value.mul(totalLiquidity).div(ethReserve);
		liquidity[msg.sender] = liquidity[msg.sender].add(liquidityMinted);
		totalLiquidity = totalLiquidity.add(liquidityMinted);

		require(
			token.transferFrom(msg.sender, address(this), tokenDeposit),
			"DEX: transfer failed"
		);

		emit LiquidityProvided(
			msg.sender,
			liquidityMinted,
			msg.value,
			tokenDeposit
		);
		return tokenDeposit;
	}

	function withdraw(
		uint256 amount
	)
		external
		nonReentrant
		notStopped
		returns (uint256 eth_amount, uint256 token_amount)
	{
		require(liquidity[msg.sender] >= amount, "DEX: insufficient liquidity");
		uint256 ethReserve = address(this).balance;
		uint256 tokenReserve = token.balanceOf(address(this));

		eth_amount = amount.mul(ethReserve).div(totalLiquidity);
		token_amount = amount.mul(tokenReserve).div(totalLiquidity);

		liquidity[msg.sender] = liquidity[msg.sender].sub(amount);
		totalLiquidity = totalLiquidity.sub(amount);

		(bool sent, ) = msg.sender.call{ value: eth_amount }("");
		require(sent, "DEX: ETH transfer failed");
		require(
			token.transfer(msg.sender, token_amount),
			"DEX: token transfer failed"
		);

		emit LiquidityRemoved(msg.sender, amount, token_amount, eth_amount);
		return (eth_amount, token_amount);
	}

	receive() external payable {}
	fallback() external payable {}
}
