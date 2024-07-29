import { ethers } from "hardhat";
import { expect } from "chai";
import { ContractTransactionReceipt } from "ethers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { Balloons, DEX } from "../typechain-types";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";

describe("DEX", function () {
    async function deployDEXFixture() {
        const [owner, user1, user2] = await ethers.getSigners();

        const Balloons = await ethers.getContractFactory("Balloons");
        const balloons = await Balloons.deploy();

        const DEX = await ethers.getContractFactory("DEX");
        const dex = await DEX.deploy(await balloons.getAddress());

        // Mint some tokens to users
        await balloons.transfer(user1.address, ethers.parseEther("100"));
        await balloons.transfer(user2.address, ethers.parseEther("100"));

        return { dex, balloons, owner, user1, user2 };
    }

    describe("Deployment", function () {
        it("Should set the right token address", async function () {
            const { dex, balloons } = await loadFixture(deployDEXFixture);
            expect(await dex.token()).to.equal(await balloons.getAddress());
        });

        it("Should set the right owner", async function () {
            const { dex, owner } = await loadFixture(deployDEXFixture);
            expect(await dex.owner()).to.equal(owner.address);
        });
    });

    describe("Initialization", function () {
        it("Should initialize with correct liquidity", async function () {
            const { dex, balloons, owner } = await loadFixture(deployDEXFixture);
            await balloons.approve(await dex.getAddress(), ethers.parseEther("5"));
            await dex.init(ethers.parseEther("5"), { value: ethers.parseEther("5") });

            expect(await dex.totalLiquidity()).to.equal(ethers.parseEther("5"));
            expect(await dex.getLiquidity(owner.address)).to.equal(ethers.parseEther("5"));
        });

        it("Should revert if trying to initialize twice", async function () {
            const { dex, balloons, owner } = await loadFixture(deployDEXFixture);
            await balloons.approve(await dex.getAddress(), ethers.parseEther("5"));
            await dex.init(ethers.parseEther("5"), { value: ethers.parseEther("5") });

            await expect(dex.init(ethers.parseEther("5"), { value: ethers.parseEther("5") }))
                .to.be.revertedWith("DEX: already initialized");
        });
    });

    describe("Price Calculation", function () {
        it("Should calculate price correctly for different reserves", async function () {
            const { dex } = await loadFixture(deployDEXFixture);
            const price = await dex.price(ethers.parseEther("1"), ethers.parseEther("20"), ethers.parseEther("5"));
            
            // Calculate the expected price
            const inputAmount = ethers.parseEther("1");
            const inputReserve = ethers.parseEther("20");
            const outputReserve = ethers.parseEther("5");
            const inputAmountWithFee = inputAmount * 997n;
            const numerator = inputAmountWithFee * outputReserve;
            const denominator = inputReserve * 1000n + inputAmountWithFee;
            const expectedPrice = numerator / denominator;
          
            expect(price).to.equal(expectedPrice);
          
            // For human-readable comparison
            console.log("Calculated price:", ethers.formatEther(price));
            console.log("Expected price:", ethers.formatEther(expectedPrice));
          });
    });
    
    describe("Price Calculation2", function () {
        it("Should calculate price correctly", async function () {
            const { dex } = await loadFixture(deployDEXFixture);
            const price = await dex.price(ethers.parseEther("1"), ethers.parseEther("10"), ethers.parseEther("10"));

            // Calculate the expected price
            const inputAmount = ethers.parseEther("1");
            const inputReserve = ethers.parseEther("10");
            const outputReserve = ethers.parseEther("10");
            const inputAmountWithFee = inputAmount * 997n;
            const numerator = inputAmountWithFee * outputReserve;
            const denominator = inputReserve * 1000n + inputAmountWithFee;
            const expectedPrice = numerator / denominator;

            expect(price).to.equal(expectedPrice);

            // For human-readable comparison
            console.log("Calculated price:", ethers.formatEther(price));
            console.log("Expected price:", ethers.formatEther(expectedPrice));
        });


        it("Should revert with invalid reserves", async function () {
            const { dex } = await loadFixture(deployDEXFixture);
            await expect(dex.price(ethers.parseEther("1"), 0, ethers.parseEther("10")))
                .to.be.revertedWith("DEX: invalid reserves");
        });
    });



    describe("Swapping", function () {
        it("Should swap ETH to token correctly", async function () {
            const { dex, balloons, owner, user1 } = await loadFixture(deployDEXFixture);
            await balloons.approve(await dex.getAddress(), ethers.parseEther("10"));
            await dex.init(ethers.parseEther("10"), { value: ethers.parseEther("10") });

            await expect(dex.connect(user1).ethToToken({ value: ethers.parseEther("1") }))
                .to.emit(dex, "EthToTokenSwap")
                .withArgs(user1.address, anyValue, ethers.parseEther("1"));

            expect(await balloons.balanceOf(user1.address)).to.be.above(0);
        });

        it("Should swap token to ETH correctly", async function () {
            const { dex, balloons, owner, user1 } = await loadFixture(deployDEXFixture);
            await balloons.approve(await dex.getAddress(), ethers.parseEther("10"));
            await dex.init(ethers.parseEther("10"), { value: ethers.parseEther("10") });

            await balloons.connect(user1).approve(await dex.getAddress(), ethers.parseEther("1"));
            await expect(dex.connect(user1).tokenToEth(ethers.parseEther("1")))
                .to.emit(dex, "TokenToEthSwap")
                .withArgs(user1.address, ethers.parseEther("1"), anyValue);

            expect(await ethers.provider.getBalance(await dex.getAddress())).to.be.below(ethers.parseEther("10"));
        });
    });

    describe("Liquidity", function () {
        it("Should allow depositing liquidity", async function () {
            const { dex, balloons, user1 } = await loadFixture(deployDEXFixture);
            await balloons.approve(await dex.getAddress(), ethers.parseEther("10"));
            await dex.init(ethers.parseEther("10"), { value: ethers.parseEther("10") });

            await balloons.connect(user1).approve(await dex.getAddress(), ethers.parseEther("1"));
            await expect(dex.connect(user1).deposit({ value: ethers.parseEther("1") }))
                .to.emit(dex, "LiquidityProvided")
                .withArgs(user1.address, anyValue, ethers.parseEther("1"), anyValue);

            expect(await dex.getLiquidity(user1.address)).to.be.above(0);
        });

        it("Should allow withdrawing liquidity", async function () {
            const { dex, balloons, owner } = await loadFixture(deployDEXFixture);
            await balloons.approve(await dex.getAddress(), ethers.parseEther("10"));
            await dex.init(ethers.parseEther("10"), { value: ethers.parseEther("10") });

            await expect(dex.withdraw(ethers.parseEther("5")))
                .to.emit(dex, "LiquidityRemoved")
                .withArgs(owner.address, ethers.parseEther("5"), anyValue, anyValue);

            expect(await dex.getLiquidity(owner.address)).to.equal(ethers.parseEther("5"));
        });
    });

    describe("Emergency Stop", function () {
        it("Should allow owner to set emergency stop", async function () {
            const { dex, owner } = await loadFixture(deployDEXFixture);
            await expect(dex.connect(owner).setEmergencyStop(true))
                .to.emit(dex, "EmergencyStopSet")
                .withArgs(true);

            expect(await dex.emergencyStop()).to.be.true;
        });

        it("Should prevent swaps when emergency stop is active", async function () {
            const { dex, balloons, owner, user1 } = await loadFixture(deployDEXFixture);
            await balloons.approve(await dex.getAddress(), ethers.parseEther("10"));
            await dex.init(ethers.parseEther("10"), { value: ethers.parseEther("10") });

            await dex.connect(owner).setEmergencyStop(true);

            await expect(dex.connect(user1).ethToToken({ value: ethers.parseEther("1") }))
                .to.be.revertedWith("DEX: Emergency stop is active");
        });
    });
});