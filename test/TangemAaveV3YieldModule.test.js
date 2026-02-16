const { expect } = require("chai");
const { ethers } = require("hardhat");
const { deployTestSetup } = require("../scripts/TestDeploy");

describe("TangemBridgeProcessor", function () {
  const PRECISION = 10000;
  let yieldToken, factory, processor, pool, forwarder, protocolToken, swapExecutionRegistry, backend, owner, otherAccount;

  before(async function () {
    [ backend, owner, otherAccount ] = await ethers.getSigners();
  });

  beforeEach(async function () {
    ( { yieldToken, factory, processor, pool, forwarder, swapExecutionRegistry } = await deployTestSetup() );

    protocolTokenAddress = await pool.aToken();
    const TestERC20 = await ethers.getContractFactory("TestERC20");
    protocolToken = TestERC20.attach(protocolTokenAddress);
  });

  describe("Deployment", function () {
    let yieldModule;

    beforeEach(async function () {
      yieldModule = null;
    });

    async function deploy(owner, yieldToken, maxNetworkFee) {
      const deployTx = await factory.connect(owner).deployYieldModule(owner, yieldToken, maxNetworkFee);
      await deployTx.wait();

      const TangemAaveV3YieldModule = await ethers.getContractFactory("TangemAaveV3YieldModule");
      const yieldModuleAddress = await factory.calculateYieldModuleAddress(owner);
      yieldModule = TangemAaveV3YieldModule.attach(yieldModuleAddress)

      return deployTx;
    }

    it("Should set specified owner", async function () {
      await deploy(owner, ethers.ZeroAddress, 0);

      expect(await yieldModule.owner()).to.equal(owner);
    });

    it("Should initialize specified yield token with specified network fee", async function () {
      const maxNetworkFee = 12345;

      await deploy(owner, yieldToken, maxNetworkFee);

      const yieldTokenData = await yieldModule.yieldTokensData(yieldToken);
      expect(yieldTokenData.initialized).to.be.true;
      expect(yieldTokenData.active).to.be.true;
      expect(yieldTokenData.maxNetworkFee).to.equal(maxNetworkFee);

      expect(await yieldModule.protocolTokens(yieldToken)).to.equal(protocolToken);
      expect(await yieldModule.isProtocolToken(protocolToken)).to.be.true;
    });

    it("Should emit YieldTokenInitialized event", async function () {
      const maxNetworkFee = 345345;
      const expectedYieldModuleAddress = await factory.calculateYieldModuleAddress(owner);
      const TangemAaveV3YieldModule = await ethers.getContractFactory("TangemAaveV3YieldModule");
      const expectedYieldModule = TangemAaveV3YieldModule.attach(expectedYieldModuleAddress);

      await expect(deploy(owner, yieldToken, maxNetworkFee))
        .to.emit(expectedYieldModule, "YieldTokenInitialized")
        .withArgs(yieldToken, protocolToken, maxNetworkFee);
    });
  });

  describe("initYieldToken", function () {
    const maxNetworkFee = 42556;
    let yieldModule;

    beforeEach(async function () {
      const deployTx = await factory.connect(owner).deployYieldModule(owner, ethers.ZeroAddress, 0);
      await deployTx.wait();

      const TangemAaveV3YieldModule = await ethers.getContractFactory("TangemAaveV3YieldModule");
      const yieldModuleAddress = await factory.calculateYieldModuleAddress(owner);
      yieldModule = TangemAaveV3YieldModule.attach(yieldModuleAddress)
    });

    it("Should initialize specified yield token with specified network fee", async function () {
      await yieldModule.connect(owner).initYieldToken(yieldToken, maxNetworkFee);

      const yieldTokenData = await yieldModule.yieldTokensData(yieldToken);
      expect(yieldTokenData.initialized).to.be.true;
      expect(yieldTokenData.active).to.be.true;
      expect(yieldTokenData.maxNetworkFee).to.equal(maxNetworkFee);

      expect(await yieldModule.protocolTokens(yieldToken)).to.equal(protocolToken);
      expect(await yieldModule.isProtocolToken(protocolToken)).to.be.true;
    });

    it("Should fail with correct error if called not by owner or factory", async function () {
      await expect(yieldModule.initYieldToken(yieldToken, maxNetworkFee))
        .to.be.revertedWithCustomError(yieldModule, "OnlyOwnerOrFactory");
    });

    it("Should emit YieldTokenInitialized event", async function () {
      await expect(yieldModule.connect(owner).initYieldToken(yieldToken, maxNetworkFee))
        .to.emit(yieldModule, "YieldTokenInitialized")
        .withArgs(yieldToken, protocolToken, maxNetworkFee);
    });
  });

  describe("enterProtocolByOwner", function () {
    const maxNetworkFee = 12345;
    const initialOwnerBalance = 223556;
    const initialModuleBalance = 1235;
    let yieldModule;

    beforeEach(async function () {
      const deployTx = await factory.connect(owner).deployYieldModule(owner, yieldToken, maxNetworkFee);
      await deployTx.wait();

      const TangemAaveV3YieldModule = await ethers.getContractFactory("TangemAaveV3YieldModule");
      const yieldModuleAddress = await factory.calculateYieldModuleAddress(owner);
      yieldModule = TangemAaveV3YieldModule.attach(yieldModuleAddress)

      const mintTx1 = await yieldToken.mint(owner, initialOwnerBalance);
      await mintTx1.wait()

      const mintTx2 = await yieldToken.mint(yieldModule, initialModuleBalance);
      await mintTx2.wait()

      const approveTx = await yieldToken.connect(owner).approve(yieldModule, ethers.MaxUint256);
      await approveTx.wait();
    });

    it("Should initiate yield token transfer of all the user funds to the module", async function () {
      await expect(yieldModule.connect(owner).enterProtocolByOwner(yieldToken))
        .to.emit(yieldToken, "Transfer")
        .withArgs(owner, yieldModule, initialOwnerBalance);
    });

    it("Should initiate yield token approval of owner balance + module balance to the AAVE pool", async function () {
      const expectedAmount = initialOwnerBalance + initialModuleBalance;

      await expect(yieldModule.connect(owner).enterProtocolByOwner(yieldToken))
        .to.emit(yieldToken, "Approval")
        .withArgs(yieldModule, pool, expectedAmount);
    });

    it("Should initiate AAVE pool supply of yield token with owner balance + module balance on behalf of itself", async function () {
      const expectedAmount = initialOwnerBalance + initialModuleBalance;

      await expect(yieldModule.connect(owner).enterProtocolByOwner(yieldToken))
        .to.emit(pool, "Supply")
        .withArgs(yieldToken, expectedAmount, yieldModule, 0);
    });

    it("Should fail with correct error if called not by owner", async function () {
      await expect(yieldModule.enterProtocolByOwner(yieldToken))
        .to.be.revertedWithCustomError(yieldModule, "OnlyOwner");
    });

    it("Should emit ProtocolEntered event with correct parameters", async function () {
      const expectedAmount = initialOwnerBalance + initialModuleBalance;
      const expectedNetworkFee = 0;

      await expect(yieldModule.connect(owner).enterProtocolByOwner(yieldToken))
        .to.emit(yieldModule, "ProtocolEntered")
        .withArgs(yieldToken, expectedAmount, expectedNetworkFee);
    });

    describe("Fee processing", function () {

      describe("First enter", function () {

        it("Should set latest fee payment state", async function () {
          const expectedProtocolBalance = initialOwnerBalance + initialModuleBalance;
          const expectedFeeRate = await processor.serviceFeeRate();

          let latestFeePaymentState = await yieldModule.latestFeePaymentStates(yieldToken);
          expect(latestFeePaymentState.protocolBalance).to.equal(0);
          expect(latestFeePaymentState.serviceFeeRate).to.equal(0);

          const enterTx = await yieldModule.connect(owner).enterProtocolByOwner(yieldToken);
          await enterTx.wait();

          latestFeePaymentState = await yieldModule.latestFeePaymentStates(yieldToken);
          expect(latestFeePaymentState.protocolBalance).to.equal(expectedProtocolBalance);
          expect(latestFeePaymentState.serviceFeeRate).to.equal(expectedFeeRate);
        });

        it("Should emit FeePaymentFailed event with correct parameters", async function () {
          const expectedAmount = 0;

          await expect(yieldModule.connect(owner).enterProtocolByOwner(yieldToken))
            .to.emit(yieldModule, "FeePaymentFailed")
            .withArgs(yieldToken, expectedAmount);
        });
      });

      describe("Consecutive enters", function () {
        const freshOwnerBalance = 453456;
        const accumulatedRevenue = 23566;
        const newFeeRate = 2444;
        const initialProtocolBalance = initialOwnerBalance + initialModuleBalance;
        let initialFeeRate, serviceFee, feeReceiver;

        beforeEach(async function () {
          initialFeeRate = await processor.serviceFeeRate();
          serviceFee = Math.floor(accumulatedRevenue * Number(initialFeeRate) / PRECISION);
          feeReceiver = await processor.feeReceiver();

          const enterTx = await yieldModule.connect(owner).enterProtocolByOwner(yieldToken);
          await enterTx.wait();

          const mintTx = await yieldToken.mint(owner, freshOwnerBalance);
          await mintTx.wait();

          const generateTx = await pool.generateRevenue(yieldModule, accumulatedRevenue);
          await generateTx.wait();

          const setTx = await processor.setServiceFeeRate(newFeeRate);
          await setTx.wait();
        });

        it("Should update latest fee payment state", async function () {
          const expectedProtocolBalance = initialProtocolBalance + accumulatedRevenue + freshOwnerBalance - serviceFee;
          const expectedFeeRate = newFeeRate;

          let latestFeePaymentState = await yieldModule.latestFeePaymentStates(yieldToken);
          expect(latestFeePaymentState.protocolBalance).to.equal(initialProtocolBalance);
          expect(latestFeePaymentState.serviceFeeRate).to.equal(initialFeeRate);

          const enterTx = await yieldModule.connect(owner).enterProtocolByOwner(yieldToken);
          await enterTx.wait();

          latestFeePaymentState = await yieldModule.latestFeePaymentStates(yieldToken);
          expect(latestFeePaymentState.protocolBalance).to.equal(expectedProtocolBalance);
          expect(latestFeePaymentState.serviceFeeRate).to.equal(expectedFeeRate);
        });

        it("Should initiate protocol token transfer of service fee to fee receiver", async function () {
          await expect(yieldModule.connect(owner).enterProtocolByOwner(yieldToken))
            .to.emit(protocolToken, "Transfer")
            .withArgs(yieldModule, feeReceiver, serviceFee);
        });

        it("Should emit FeePaymentProcessed event with correct parameters", async function () {
          const expectedAmount = serviceFee;

          await expect(yieldModule.connect(owner).enterProtocolByOwner(yieldToken))
            .to.emit(yieldModule, "FeePaymentProcessed")
            .withArgs(yieldToken, expectedAmount, feeReceiver);
        });
      });
    });
  });

  describe("enterProtocol", function () {
    const maxNetworkFee = 12345;
    const networkFee = 1234;
    const initialOwnerBalance = 464263;
    const initialModuleBalance = 53245;
    let yieldModule;

    beforeEach(async function () {
      const deployTx = await factory.connect(owner).deployYieldModule(owner, yieldToken, maxNetworkFee);
      await deployTx.wait();

      const TangemAaveV3YieldModule = await ethers.getContractFactory("TangemAaveV3YieldModule");
      const yieldModuleAddress = await factory.calculateYieldModuleAddress(owner);
      yieldModule = TangemAaveV3YieldModule.attach(yieldModuleAddress)

      const mintTx1 = await yieldToken.mint(owner, initialOwnerBalance);
      await mintTx1.wait()

      const mintTx2 = await yieldToken.mint(yieldModule, initialModuleBalance);
      await mintTx2.wait()

      const approveTx = await yieldToken.connect(owner).approve(yieldModule, ethers.MaxUint256);
      await approveTx.wait();
    });

    it("Should initiate yield token transfer of all the user funds to the module", async function () {
      await expect(processor.enterProtocol(yieldModule, yieldToken, networkFee))
        .to.emit(yieldToken, "Transfer")
        .withArgs(owner, yieldModule, initialOwnerBalance);
    });

    it("Should initiate yield token approval of owner balance + module balance to the AAVE pool", async function () {
      const expectedAmount = initialOwnerBalance + initialModuleBalance;

      await expect(processor.enterProtocol(yieldModule, yieldToken, networkFee))
        .to.emit(yieldToken, "Approval")
        .withArgs(yieldModule, pool, expectedAmount);
    });

    it("Should initiate AAVE pool supply of yield token with owner balance + module balance on behalf of itself", async function () {
      const expectedAmount = initialOwnerBalance + initialModuleBalance;

      await expect(processor.enterProtocol(yieldModule, yieldToken, networkFee))
        .to.emit(pool, "Supply")
        .withArgs(yieldToken, expectedAmount, yieldModule, 0);
    });

    it("Should fail with correct error if network fee exceeds maximum", async function () {
      await expect(processor.enterProtocol(yieldModule, yieldToken, maxNetworkFee + 1))
        .to.be.revertedWithCustomError(yieldModule, "NetworkFeeExceedsMax");
    });

    it("Should fail with correct error if network fee >= enter amount", async function () {
      const enterTx = await processor.enterProtocol(yieldModule, yieldToken, networkFee)
      await enterTx.wait();

      const mintTx = await yieldToken.mint(owner, networkFee);
      await mintTx.wait();

      await expect(processor.enterProtocol(yieldModule, yieldToken, networkFee))
        .to.be.revertedWithCustomError(yieldModule, "NetworkFeeExceedsAmount");
    });

    it("Should fail with correct error if called not by processor", async function () {
      await expect(yieldModule.enterProtocol(yieldToken, networkFee))
        .to.be.revertedWithCustomError(yieldModule, "OnlyProcessor");
    });

    it("Should emit ProtocolEntered event with correct parameters", async function () {
      const expectedAmount = initialOwnerBalance + initialModuleBalance;
      const expectedNetworkFee = networkFee;

      await expect(processor.enterProtocol(yieldModule, yieldToken, networkFee))
        .to.emit(yieldModule, "ProtocolEntered")
        .withArgs(yieldToken, expectedAmount, expectedNetworkFee);
    });

    describe("Fee processing", function () {
      let feeReceiver;

      beforeEach(async function () {
          feeReceiver = await processor.feeReceiver();
        });

      describe("First enter", function () {

        it("Should set latest fee payment state", async function () {
          const expectedProtocolBalance = initialOwnerBalance + initialModuleBalance - networkFee;
          const expectedFeeRate = await processor.serviceFeeRate();

          let latestFeePaymentState = await yieldModule.latestFeePaymentStates(yieldToken);
          expect(latestFeePaymentState.protocolBalance).to.equal(0);
          expect(latestFeePaymentState.serviceFeeRate).to.equal(0);

          const enterTx = await processor.enterProtocol(yieldModule, yieldToken, networkFee);
          await enterTx.wait();

          latestFeePaymentState = await yieldModule.latestFeePaymentStates(yieldToken);
          expect(latestFeePaymentState.protocolBalance).to.equal(expectedProtocolBalance);
          expect(latestFeePaymentState.serviceFeeRate).to.equal(expectedFeeRate);
        });

        it("Should initiate protocol token transfer of network fee to fee receiver", async function () {
          await expect(processor.enterProtocol(yieldModule, yieldToken, networkFee))
            .to.emit(protocolToken, "Transfer")
            .withArgs(yieldModule, feeReceiver, networkFee);
        });

        it("Should emit FeePaymentProcessed event with correct parameters", async function () {
          const expectedAmount = networkFee;

          await expect(processor.enterProtocol(yieldModule, yieldToken, networkFee))
            .to.emit(yieldModule, "FeePaymentProcessed")
            .withArgs(yieldToken, expectedAmount, feeReceiver);
        });
      });

      describe("Consecutive enters", function () {
        const freshOwnerBalance = 46436;
        const accumulatedRevenue = 11435;
        const newFeeRate = 1234;
        const initialProtocolBalance = initialOwnerBalance + initialModuleBalance;
        let initialFeeRate, serviceFee, feeReceiver;

        beforeEach(async function () {
          initialFeeRate = await processor.serviceFeeRate();
          serviceFee = Math.floor(accumulatedRevenue * Number(initialFeeRate) / PRECISION);
          feeReceiver = await processor.feeReceiver();

          const enterTx = await yieldModule.connect(owner).enterProtocolByOwner(yieldToken);
          await enterTx.wait();

          const mintTx = await yieldToken.mint(owner, freshOwnerBalance);
          await mintTx.wait();

          const generateTx = await pool.generateRevenue(yieldModule, accumulatedRevenue);
          await generateTx.wait();

          const setTx = await processor.setServiceFeeRate(newFeeRate);
          await setTx.wait();
        });

        it("Should update latest fee payment state", async function () {
          const expectedProtocolBalance =
            initialProtocolBalance + accumulatedRevenue + freshOwnerBalance - serviceFee - networkFee;
          const expectedFeeRate = newFeeRate;

          let latestFeePaymentState = await yieldModule.latestFeePaymentStates(yieldToken);
          expect(latestFeePaymentState.protocolBalance).to.equal(initialProtocolBalance);
          expect(latestFeePaymentState.serviceFeeRate).to.equal(initialFeeRate);

          const enterTx = await processor.enterProtocol(yieldModule, yieldToken, networkFee);
          await enterTx.wait();

          latestFeePaymentState = await yieldModule.latestFeePaymentStates(yieldToken);
          expect(latestFeePaymentState.protocolBalance).to.equal(expectedProtocolBalance);
          expect(latestFeePaymentState.serviceFeeRate).to.equal(expectedFeeRate);
        });

        it("Should initiate protocol token transfer of service fee + network fee to fee receiver", async function () {
          const expectedAmount = serviceFee + networkFee;

          await expect(processor.enterProtocol(yieldModule, yieldToken, networkFee))
            .to.emit(protocolToken, "Transfer")
            .withArgs(yieldModule, feeReceiver, expectedAmount);
        });

        it("Should emit FeePaymentProcessed event with correct parameters", async function () {
          const expectedAmount = serviceFee + networkFee;

          await expect(processor.enterProtocol(yieldModule, yieldToken, networkFee))
            .to.emit(yieldModule, "FeePaymentProcessed")
            .withArgs(yieldToken, expectedAmount, feeReceiver);
        });
      });
    });
  });

  describe("exitProtocol", function () {
    const maxNetworkFee = 12345;
    const networkFee = 1234;
    const initialOwnerBalance = 464263;
    const accumulatedRevenue = 11435;
    const protocolBalance = initialOwnerBalance + accumulatedRevenue;
    let yieldModule, serviceFee, initialFeeRate;

    beforeEach(async function () {
      const deployTx = await factory.connect(owner).deployYieldModule(owner, yieldToken, maxNetworkFee);
      await deployTx.wait();

      const TangemAaveV3YieldModule = await ethers.getContractFactory("TangemAaveV3YieldModule");
      const yieldModuleAddress = await factory.calculateYieldModuleAddress(owner);
      yieldModule = TangemAaveV3YieldModule.attach(yieldModuleAddress)

      const mintTx = await yieldToken.mint(owner, initialOwnerBalance);
      await mintTx.wait()

      const approveTx = await yieldToken.connect(owner).approve(yieldModule, ethers.MaxUint256);
      await approveTx.wait();

      const enterTx = await processor.enterProtocol(yieldModule, yieldToken, 0);
      await enterTx.wait();

      const generateTx = await pool.generateRevenue(yieldModule, accumulatedRevenue);
      await generateTx.wait();

      initialFeeRate = await processor.serviceFeeRate()
      serviceFee = Math.floor(accumulatedRevenue * Number(initialFeeRate) / PRECISION);
    });

    it("Should initiate AAVE pool withdrawal of total protocol balance of yield token to owner", async function () {
      const expectedAmount = protocolBalance;

      await expect(processor.exitProtocol(yieldModule, yieldToken, networkFee))
        .to.emit(pool, "Withdraw")
        .withArgs(yieldToken, expectedAmount, owner);
    });

    it("Should deactivate specified yield token", async function () {
      let yieldTokenData = await yieldModule.yieldTokensData(yieldToken);
      expect(yieldTokenData.active).to.be.true;

      const exitTx = await processor.exitProtocol(yieldModule, yieldToken, networkFee);
      await exitTx.wait();

      yieldTokenData = await yieldModule.yieldTokensData(yieldToken);
      expect(yieldTokenData.active).to.be.false;
    });

    it("Should fail with correct error if network fee exceeds maximum", async function () {
      await expect(processor.exitProtocol(yieldModule, yieldToken, maxNetworkFee + 1))
        .to.be.revertedWithCustomError(yieldModule, "NetworkFeeExceedsMax");
    });

    it("Should fail with correct error if called not by processor", async function () {
      await expect(yieldModule.exitProtocol(yieldToken, networkFee))
        .to.be.revertedWithCustomError(yieldModule, "OnlyProcessor");
    });

    it("Should emit ProtocolExited event with correct parameters", async function () {
      const expectedAmount = protocolBalance;
      const expectedNetworkFee = networkFee;

      await expect(processor.exitProtocol(yieldModule, yieldToken, networkFee))
        .to.emit(yieldModule, "ProtocolExited")
        .withArgs(yieldToken, expectedAmount, expectedNetworkFee);
    });

    describe("Fee processing", function () {
      let feeReceiver;

      beforeEach(async function () {
          feeReceiver = await processor.feeReceiver();
        });

      it("Should set latest fee payment state", async function () {
        const newFeeRate = 333;
        const setTx = await processor.setServiceFeeRate(newFeeRate);
        await setTx.wait();

        const expectedProtocolBalance = 0;
        const expectedFeeRate = newFeeRate;

        let latestFeePaymentState = await yieldModule.latestFeePaymentStates(yieldToken);
        expect(latestFeePaymentState.protocolBalance).to.equal(initialOwnerBalance);
        expect(latestFeePaymentState.serviceFeeRate).to.equal(initialFeeRate);

        const exitTx = await processor.exitProtocol(yieldModule, yieldToken, networkFee);
        await exitTx.wait();

        latestFeePaymentState = await yieldModule.latestFeePaymentStates(yieldToken);
        expect(latestFeePaymentState.protocolBalance).to.equal(expectedProtocolBalance);
        expect(latestFeePaymentState.serviceFeeRate).to.equal(expectedFeeRate);
      });

      it("Should initiate yield token transfer of service and network fee from owner to fee receiver", async function () {
        const expectedAmount = serviceFee + networkFee;
        
        await expect(processor.exitProtocol(yieldModule, yieldToken, networkFee))
          .to.emit(yieldToken, "Transfer")
          .withArgs(owner, feeReceiver, expectedAmount);
      });

      it("Should emit FeePaymentProcessed event with correct parameters", async function () {
        const expectedAmount = networkFee + serviceFee;

        await expect(processor.exitProtocol(yieldModule, yieldToken, networkFee))
          .to.emit(yieldModule, "FeePaymentProcessed")
          .withArgs(yieldToken, expectedAmount, feeReceiver);
      });
    });
  });

  describe("send", function () {
    const maxNetworkFee = 12345;
    const initialOwnerBalance = 464263;
    const accumulatedRevenue = 11435;
    const protocolBalance = initialOwnerBalance + accumulatedRevenue;
    const freshOwnerBalance = 5256;
    const sendAmount = 25643;
    let yieldModule, serviceFee, initialFeeRate, receiver;

    before(async function () {
      receiver = otherAccount;
    });

    beforeEach(async function () {
      const deployTx = await factory.connect(owner).deployYieldModule(owner, yieldToken, maxNetworkFee);
      await deployTx.wait();

      const TangemAaveV3YieldModule = await ethers.getContractFactory("TangemAaveV3YieldModule");
      const yieldModuleAddress = await factory.calculateYieldModuleAddress(owner);
      yieldModule = TangemAaveV3YieldModule.attach(yieldModuleAddress)

      const mintTx1 = await yieldToken.mint(owner, initialOwnerBalance);
      await mintTx1.wait()

      const approveTx = await yieldToken.connect(owner).approve(yieldModule, ethers.MaxUint256);
      await approveTx.wait();

      const enterTx = await processor.enterProtocol(yieldModule, yieldToken, 0);
      await enterTx.wait();

      const mintTx2 = await yieldToken.mint(owner, freshOwnerBalance);
      await mintTx2.wait()

      const generateTx = await pool.generateRevenue(yieldModule, accumulatedRevenue);
      await generateTx.wait();

      initialFeeRate = await processor.serviceFeeRate()
      serviceFee = Math.floor(accumulatedRevenue * Number(initialFeeRate) / PRECISION);
    });

    it("Should initiate AAVE pool withdrawal of specified amount - owner's balance of yield token to owner", async function () {
      const expectedAmount = sendAmount - freshOwnerBalance;

      await expect(yieldModule.connect(owner).send(yieldToken, receiver, sendAmount))
        .to.emit(pool, "Withdraw")
        .withArgs(yieldToken, expectedAmount, owner);
    });

    it("Should not initiate AAVE pool withdrawal if the owner's balance is more than amount", async function () {
      const mintTx = await yieldToken.mint(owner, sendAmount);
      await mintTx.wait()

      await expect(yieldModule.connect(owner).send(yieldToken, receiver, sendAmount))
        .to.not.emit(pool, "Withdraw");
    });

    it("Should initiate yield token transfer of specified amount from the owner to the receiver", async function () {
      await expect(yieldModule.connect(owner).send(yieldToken, receiver, sendAmount))
        .to.emit(yieldToken, "Transfer")
        .withArgs(owner, receiver, sendAmount);
    });

    it("Should fail with correct error if receiver is owner", async function () {
      await expect(yieldModule.connect(owner).send(yieldToken, owner, sendAmount))
        .to.be.revertedWithCustomError(yieldModule, "SendingToOwner");
    });

    it("Should fail with correct error if called not by owner", async function () {
      await expect(yieldModule.send(yieldToken, receiver, sendAmount))
        .to.be.revertedWithCustomError(yieldModule, "OnlyOwner");
    });

    it("Should emit SendProcessed event with correct parameters", async function () {
      await expect(yieldModule.connect(owner).send(yieldToken, receiver, sendAmount))
        .to.emit(yieldModule, "SendProcessed")
        .withArgs(yieldToken, receiver, sendAmount);
    });

    describe("Fee processing", function () {
      let feeReceiver;

      beforeEach(async function () {
          feeReceiver = await processor.feeReceiver();
        });

      it("Should set latest fee payment state", async function () {
        const newFeeRate = 333;
        const setTx = await processor.setServiceFeeRate(newFeeRate);
        await setTx.wait();

        const expectedProtocolBalance = protocolBalance - sendAmount - serviceFee + freshOwnerBalance;
        const expectedFeeRate = newFeeRate;

        let latestFeePaymentState = await yieldModule.latestFeePaymentStates(yieldToken);
        expect(latestFeePaymentState.protocolBalance).to.equal(initialOwnerBalance);
        expect(latestFeePaymentState.serviceFeeRate).to.equal(initialFeeRate);

        const sendTx = await yieldModule.connect(owner).send(yieldToken, receiver, sendAmount);
        await sendTx.wait();

        latestFeePaymentState = await yieldModule.latestFeePaymentStates(yieldToken);
        expect(latestFeePaymentState.protocolBalance).to.equal(expectedProtocolBalance);
        expect(latestFeePaymentState.serviceFeeRate).to.equal(expectedFeeRate);
      });

      it("Should initiate protocol token transfer of service fee to fee receiver", async function () {
        const expectedAmount = serviceFee;
        
        await expect(yieldModule.connect(owner).send(yieldToken, receiver, sendAmount))
          .to.emit(protocolToken, "Transfer")
          .withArgs(yieldModule, feeReceiver, expectedAmount);
      });

      it("Should not process fee if the owner's balance is more than amount", async function () {
        const mintTx1 = await yieldToken.mint(owner, sendAmount);
        await mintTx1.wait()

        await expect(yieldModule.connect(owner).send(yieldToken, receiver, sendAmount))
          .to.not.emit(yieldModule, "FeePaymentProcessed");

        const mintTx2 = await yieldToken.mint(owner, sendAmount);
        await mintTx2.wait()

        await expect(yieldModule.connect(owner).send(yieldToken, receiver, sendAmount))
          .to.not.emit(yieldModule, "FeePaymentFailed");
      });

      it("Should emit FeePaymentProcessed event with correct parameters", async function () {
        const expectedAmount = serviceFee;

        await expect(yieldModule.connect(owner).send(yieldToken, receiver, sendAmount))
          .to.emit(yieldModule, "FeePaymentProcessed")
          .withArgs(yieldToken, expectedAmount, feeReceiver);
      });
    });
  });

  describe("withdrawAndDeactivate", function () {
    const maxNetworkFee = 12345;
    const initialOwnerBalance = 464263;
    const accumulatedRevenue = 11435;
    const protocolBalance = initialOwnerBalance + accumulatedRevenue;
    let yieldModule, serviceFee, initialFeeRate;

    beforeEach(async function () {
      const deployTx = await factory.connect(owner).deployYieldModule(owner, yieldToken, maxNetworkFee);
      await deployTx.wait();

      const TangemAaveV3YieldModule = await ethers.getContractFactory("TangemAaveV3YieldModule");
      const yieldModuleAddress = await factory.calculateYieldModuleAddress(owner);
      yieldModule = TangemAaveV3YieldModule.attach(yieldModuleAddress)

      const mintTx = await yieldToken.mint(owner, initialOwnerBalance);
      await mintTx.wait()

      const approveTx = await yieldToken.connect(owner).approve(yieldModule, ethers.MaxUint256);
      await approveTx.wait();

      const enterTx = await processor.enterProtocol(yieldModule, yieldToken, 0);
      await enterTx.wait();

      const generateTx = await pool.generateRevenue(yieldModule, accumulatedRevenue);
      await generateTx.wait();

      initialFeeRate = await processor.serviceFeeRate()
      serviceFee = Math.floor(accumulatedRevenue * Number(initialFeeRate) / PRECISION);
    });

    it("Should initiate AAVE pool withdrawal of total protocol balance - service fee of yield token to owner", async function () {
      const expectedAmount = protocolBalance - serviceFee;

      await expect(yieldModule.connect(owner).withdrawAndDeactivate(yieldToken))
        .to.emit(pool, "Withdraw")
        .withArgs(yieldToken, expectedAmount, owner);
    });

    it("Should deactivate specified yield token", async function () {
      let yieldTokenData = await yieldModule.yieldTokensData(yieldToken);
      expect(yieldTokenData.active).to.be.true;

      const withdrawTx = await yieldModule.connect(owner).withdrawAndDeactivate(yieldToken);
      await withdrawTx.wait();

      yieldTokenData = await yieldModule.yieldTokensData(yieldToken);
      expect(yieldTokenData.active).to.be.false;
    });

    it("Should fail with correct error if called not by owner", async function () {
      await expect(yieldModule.withdrawAndDeactivate(yieldToken))
        .to.be.revertedWithCustomError(yieldModule, "OnlyOwner");
    });

    it("Should emit ProtocolExited event with correct parameters", async function () {
      const expectedAmount = protocolBalance - serviceFee;

      await expect(yieldModule.connect(owner).withdrawAndDeactivate(yieldToken))
        .to.emit(yieldModule, "WithdrawAndDeactivateProcessed")
        .withArgs(yieldToken, expectedAmount);
    });

    describe("Fee processing", function () {
      let feeReceiver;

      beforeEach(async function () {
          feeReceiver = await processor.feeReceiver();
        });

      it("Should set latest fee payment state", async function () {
        const newFeeRate = 333;
        const setTx = await processor.setServiceFeeRate(newFeeRate);
        await setTx.wait();

        const expectedProtocolBalance = 0;
        const expectedFeeRate = newFeeRate;

        let latestFeePaymentState = await yieldModule.latestFeePaymentStates(yieldToken);
        expect(latestFeePaymentState.protocolBalance).to.equal(initialOwnerBalance);
        expect(latestFeePaymentState.serviceFeeRate).to.equal(initialFeeRate);

        const enterTx = await yieldModule.connect(owner).withdrawAndDeactivate(yieldToken);
        await enterTx.wait();

        latestFeePaymentState = await yieldModule.latestFeePaymentStates(yieldToken);
        expect(latestFeePaymentState.protocolBalance).to.equal(expectedProtocolBalance);
        expect(latestFeePaymentState.serviceFeeRate).to.equal(expectedFeeRate);
      });

      it("Should initiate yield token transfer of service fee from owner to fee receiver", async function () {
        const expectedAmount = serviceFee;
        
        await expect(yieldModule.connect(owner).withdrawAndDeactivate(yieldToken))
          .to.emit(protocolToken, "Transfer")
          .withArgs(yieldModule, feeReceiver, expectedAmount);
      });

      it("Should emit FeePaymentProcessed event with correct parameters", async function () {
        const expectedAmount = serviceFee;

        await expect(yieldModule.connect(owner).withdrawAndDeactivate(yieldToken))
          .to.emit(yieldModule, "FeePaymentProcessed")
          .withArgs(yieldToken, expectedAmount, feeReceiver);
      });
    });
  });

  describe("withdrawNonYieldToken", function () {
    const moduleBalance = 4563667;
    let nonYieldToken, yieldModule;

    beforeEach(async function () {
      const deployTx = await factory.connect(owner).deployYieldModule(owner, ethers.ZeroAddress, 0);
      await deployTx.wait();

      const TangemAaveV3YieldModule = await ethers.getContractFactory("TangemAaveV3YieldModule");
      const yieldModuleAddress = await factory.calculateYieldModuleAddress(owner);
      yieldModule = TangemAaveV3YieldModule.attach(yieldModuleAddress)

      const mintTx = await yieldToken.mint(yieldModule, moduleBalance);
      await mintTx.wait();

      nonYieldToken = yieldToken;
    });

    it("Should initiate specified token transfer of total module balance from module to owner", async function () {
      await expect(yieldModule.connect(owner).withdrawNonYieldToken(nonYieldToken))
          .to.emit(nonYieldToken, "Transfer")
          .withArgs(yieldModule, owner, moduleBalance);
    });

    it("Should fail with correct error if withdrawing yield token", async function () {
      const maxNetworkFee = 6356346;
      const initTx = await yieldModule.connect(owner).initYieldToken(yieldToken, maxNetworkFee);
      await initTx.wait();

      await expect(yieldModule.connect(owner).withdrawNonYieldToken(yieldToken))
        .to.be.revertedWithCustomError(yieldModule, "WithdrawingYieldToken");
    });

    it("Should fail with correct error if withdrawing protocol token", async function () {
      const maxNetworkFee = 6356346;
      const initTx = await yieldModule.connect(owner).initYieldToken(yieldToken, maxNetworkFee);
      await initTx.wait();

      await expect(yieldModule.connect(owner).withdrawNonYieldToken(protocolToken))
        .to.be.revertedWithCustomError(yieldModule, "WithdrawingProtocolToken");
    });

    it("Should fail with correct error if called not by owner", async function () {
      await expect(yieldModule.withdrawNonYieldToken(nonYieldToken))
        .to.be.revertedWithCustomError(yieldModule, "OnlyOwner");
    });

    it("Should emit WithdrawNonYieldProcessed event", async function () {
      await expect(yieldModule.connect(owner).withdrawNonYieldToken(nonYieldToken))
        .to.emit(yieldModule, "WithdrawNonYieldProcessed")
        .withArgs(nonYieldToken, moduleBalance, );
    });
  });

  describe("collectServiceFee", function () {
    const maxNetworkFee = 12345;
    const networkFee = 1234;
    const initialOwnerBalance = 464263;
    const accumulatedRevenue = 11435;
    let yieldModule, serviceFee, initialFeeRate, feeReceiver;

    beforeEach(async function () {
      const deployTx = await factory.connect(owner).deployYieldModule(owner, yieldToken, maxNetworkFee);
      await deployTx.wait();

      const TangemAaveV3YieldModule = await ethers.getContractFactory("TangemAaveV3YieldModule");
      const yieldModuleAddress = await factory.calculateYieldModuleAddress(owner);
      yieldModule = TangemAaveV3YieldModule.attach(yieldModuleAddress)

      const mintTx = await yieldToken.mint(owner, initialOwnerBalance);
      await mintTx.wait()

      const approveTx = await yieldToken.connect(owner).approve(yieldModule, ethers.MaxUint256);
      await approveTx.wait();

      const enterTx = await processor.enterProtocol(yieldModule, yieldToken, 0);
      await enterTx.wait();

      const generateTx = await pool.generateRevenue(yieldModule, accumulatedRevenue);
      await generateTx.wait();

      initialFeeRate = await processor.serviceFeeRate()
      serviceFee = Math.floor(accumulatedRevenue * Number(initialFeeRate) / PRECISION);

      feeReceiver = await processor.feeReceiver();
    });

    it("Should set latest fee payment state", async function () {
      const newFeeRate = 2444;
      const setTx = await processor.setServiceFeeRate(newFeeRate);
      await setTx.wait();

      const expectedProtocolBalance = initialOwnerBalance + accumulatedRevenue - serviceFee;
      const expectedFeeRate = newFeeRate;

      let latestFeePaymentState = await yieldModule.latestFeePaymentStates(yieldToken);
      expect(latestFeePaymentState.protocolBalance).to.equal(initialOwnerBalance);
      expect(latestFeePaymentState.serviceFeeRate).to.equal(initialFeeRate);

      const collectTx = await processor.collectServiceFee(yieldModule, yieldToken);
      await collectTx.wait();

      latestFeePaymentState = await yieldModule.latestFeePaymentStates(yieldToken);
      expect(latestFeePaymentState.protocolBalance).to.equal(expectedProtocolBalance);
      expect(latestFeePaymentState.serviceFeeRate).to.equal(expectedFeeRate);
    });

    it("Should initiate yield token transfer of service and network fee from owner to fee receiver", async function () {
      const expectedAmount = serviceFee;
      
      await expect(processor.collectServiceFee(yieldModule, yieldToken))
        .to.emit(protocolToken, "Transfer")
        .withArgs(yieldModule, feeReceiver, expectedAmount);
    });

    it("Should fail with correct error if called not by processor", async function () {
      await expect(yieldModule.collectServiceFee(yieldToken))
        .to.be.revertedWithCustomError(yieldModule, "OnlyProcessor");
    });

    it("Should emit FeePaymentProcessed event with correct parameters", async function () {
      const expectedAmount = serviceFee;

      await expect(processor.collectServiceFee(yieldModule, yieldToken))
        .to.emit(yieldModule, "FeePaymentProcessed")
        .withArgs(yieldToken, expectedAmount, feeReceiver);
    });
  });

  describe("reactivateToken", function () {
    const maxNetworkFee = 12345;
    const newMaxNetworkFee = 35566;
    let yieldModule;

    beforeEach(async function () {
      const deployTx = await factory.connect(owner).deployYieldModule(owner, yieldToken, maxNetworkFee);
      await deployTx.wait();

      const TangemAaveV3YieldModule = await ethers.getContractFactory("TangemAaveV3YieldModule");
      const yieldModuleAddress = await factory.calculateYieldModuleAddress(owner);
      yieldModule = TangemAaveV3YieldModule.attach(yieldModuleAddress)

      const deactivateTx = await yieldModule.connect(owner).withdrawAndDeactivate(yieldToken);
      await deactivateTx.wait();
    });

    it("Should reactivate specified yield token", async function () {
      let yieldTokenData = await yieldModule.yieldTokensData(yieldToken);
      expect(yieldTokenData.active).to.be.false;

      const reactivateTx = await yieldModule.connect(owner).reactivateToken(yieldToken, newMaxNetworkFee);
      await reactivateTx.wait();

      yieldTokenData = await yieldModule.yieldTokensData(yieldToken);
      expect(yieldTokenData.active).to.be.true;
    });

    it("Should set new max network fee for specified yield token", async function () {
      let yieldTokenData = await yieldModule.yieldTokensData(yieldToken);
      expect(yieldTokenData.maxNetworkFee).to.equal(maxNetworkFee);

      const reactivateTx = await yieldModule.connect(owner).reactivateToken(yieldToken, newMaxNetworkFee);
      await reactivateTx.wait();

      yieldTokenData = await yieldModule.yieldTokensData(yieldToken);
      expect(yieldTokenData.maxNetworkFee).to.equal(newMaxNetworkFee);
    });

    it("Should fail with correct error if called not by owner", async function () {
      await expect(yieldModule.reactivateToken(yieldToken, newMaxNetworkFee))
        .to.be.revertedWithCustomError(yieldModule, "OnlyOwner");
    });

    it("Should emit TokenReactivated event with correct parameters", async function () {
      await expect(yieldModule.connect(owner).reactivateToken(yieldToken, newMaxNetworkFee))
        .to.emit(yieldModule, "TokenReactivated")
        .withArgs(yieldToken, newMaxNetworkFee);
    });
  });

  describe("setYieldTokenMaxNetworkFee", function () {
    const maxNetworkFee = 12345;
    const newMaxNetworkFee = 3255;
    let yieldModule;

    beforeEach(async function () {
      const deployTx = await factory.connect(owner).deployYieldModule(owner, yieldToken, maxNetworkFee);
      await deployTx.wait();

      const TangemAaveV3YieldModule = await ethers.getContractFactory("TangemAaveV3YieldModule");
      const yieldModuleAddress = await factory.calculateYieldModuleAddress(owner);
      yieldModule = TangemAaveV3YieldModule.attach(yieldModuleAddress)
    });

    it("Should set new max network fee for specified yield token", async function () {
      let yieldTokenData = await yieldModule.yieldTokensData(yieldToken);
      expect(yieldTokenData.maxNetworkFee).to.equal(maxNetworkFee);

      const setTx = await yieldModule.connect(owner).setYieldTokenMaxNetworkFee(yieldToken, newMaxNetworkFee);
      await setTx.wait();

      yieldTokenData = await yieldModule.yieldTokensData(yieldToken);
      expect(yieldTokenData.maxNetworkFee).to.equal(newMaxNetworkFee);
    });

    it("Should fail with correct error if called not by owner", async function () {
      await expect(yieldModule.setYieldTokenMaxNetworkFee(yieldToken, newMaxNetworkFee))
        .to.be.revertedWithCustomError(yieldModule, "OnlyOwner");
    });

    it("Should emit TokenMaxNetworkFeeSet event with correct parameters", async function () {
      await expect(yieldModule.connect(owner).setYieldTokenMaxNetworkFee(yieldToken, newMaxNetworkFee))
        .to.emit(yieldModule, "TokenMaxNetworkFeeSet")
        .withArgs(yieldToken, newMaxNetworkFee);
    });
  });

  describe("Upgrade", function () {
    const maxNetworkFee = 12345;
    const newForwarder = ethers.ZeroAddress;
    let yieldModule, newImplementation;

    beforeEach(async function () {
      const deployTx = await factory.connect(owner).deployYieldModule(owner, yieldToken, maxNetworkFee);
      await deployTx.wait();

      const TangemAaveV3YieldModule = await ethers.getContractFactory("TangemAaveV3YieldModule");
      const yieldModuleAddress = await factory.calculateYieldModuleAddress(owner);
      yieldModule = TangemAaveV3YieldModule.attach(yieldModuleAddress)

      newImplementation = await TangemAaveV3YieldModule.deploy(pool, processor, factory, newForwarder, swapExecutionRegistry);
      await newImplementation.waitForDeployment();

      const pauseTx = await factory.pause();
      await pauseTx.wait();

      const setTx = await factory.setImplementation(newImplementation);
      await setTx.wait();
    });

    it("Should upgrade to new implementation", async function () {
      expect(await yieldModule.trustedForwarder()).to.equal(forwarder);

      const exitTx = await yieldModule.connect(owner).upgradeToAndCall(newImplementation, "0x");
      await exitTx.wait();

      expect(await yieldModule.trustedForwarder()).to.equal(newForwarder);
    });

    it("Should fail with correct error if called not by owner", async function () {
      await expect(yieldModule.upgradeToAndCall(newImplementation, "0x"))
        .to.be.revertedWithCustomError(yieldModule, "OnlyOwner");
    });

    it("Should emit Upgraded event with correct parameters", async function () {
      await expect(yieldModule.connect(owner).upgradeToAndCall(newImplementation, "0x"))
        .to.emit(yieldModule, "Upgraded")
        .withArgs(newImplementation);
    });
  });

  describe("swap", function () {
    const maxNetworkFee = 12345;
    let yieldModule, yieldModuleAddress, swapProvider, swapProviderAddress;

    let ownerAddress, backendAddress, otherAddress;
    let tokenIn;

    beforeEach(async function () {
      ownerAddress = await owner.getAddress();
      backendAddress = await backend.getAddress();
      otherAddress = await otherAccount.getAddress();
      tokenIn = await yieldToken.getAddress();

      const deployTx = await factory.connect(owner).deployYieldModule(ownerAddress, tokenIn, maxNetworkFee);
      await deployTx.wait();

      const TangemAaveV3YieldModule = await ethers.getContractFactory("TangemAaveV3YieldModule");
      yieldModuleAddress = await factory.calculateYieldModuleAddress(ownerAddress);
      yieldModule = TangemAaveV3YieldModule.attach(yieldModuleAddress);

      const SwapProviderMock = await ethers.getContractFactory("SwapProviderMock");
      swapProvider = await SwapProviderMock.deploy();
      await swapProvider.waitForDeployment();
      swapProviderAddress = await swapProvider.getAddress();

      await (await swapExecutionRegistry.connect(backend).setTargetAllowed(swapProviderAddress, true)).wait();
      await (await swapExecutionRegistry.connect(backend).setSpenderAllowed(swapProviderAddress, true)).wait();

      await (await yieldToken.connect(owner).approve(yieldModuleAddress, ethers.MaxUint256)).wait();
    });

    it("Should fail with correct error if called not by owner", async function () {
      const data = swapProvider.interface.encodeFunctionData("revertEmpty", []);

      await expect(
        yieldModule.connect(backend).swap(tokenIn, 1, swapProviderAddress, ethers.ZeroAddress, data)
      ).to.be.revertedWithCustomError(yieldModule, "OnlyOwner");
    });

    it("Should fail with correct error if token is not active", async function () {
      const deactivateTx = await yieldModule.connect(owner).withdrawAndDeactivate(tokenIn);
      await deactivateTx.wait();

      const data = swapProvider.interface.encodeFunctionData("revertEmpty", []);

      await expect(
        yieldModule.connect(owner).swap(tokenIn, 1, swapProviderAddress, ethers.ZeroAddress, data)
      ).to.be.revertedWithCustomError(yieldModule, "TokenNotActive");
    });

    it("Should fail with correct error if data is too short", async function () {
      await expect(
        yieldModule.connect(owner).swap(tokenIn, 1, swapProviderAddress, ethers.ZeroAddress, "0x123456")
      ).to.be.revertedWithCustomError(yieldModule, "DataTooShort");
    });

    it("Should fail with correct error if target has no code", async function () {
      await expect(
        yieldModule.connect(owner).swap(tokenIn, 1, otherAddress, ethers.ZeroAddress, "0x12345678")
      ).to.be.revertedWithCustomError(yieldModule, "TargetHasNoCode");
    });

    it("Should fail with correct error if target is not allowed", async function () {
      const SwapProviderMock = await ethers.getContractFactory("SwapProviderMock");
      const notAllowedProvider = await SwapProviderMock.deploy();
      await notAllowedProvider.waitForDeployment();
      const notAllowedProviderAddress = await notAllowedProvider.getAddress();

      const data = notAllowedProvider.interface.encodeFunctionData("revertEmpty", []);

      await expect(
        yieldModule.connect(owner).swap(tokenIn, 1, notAllowedProviderAddress, ethers.ZeroAddress, data)
      ).to.be.revertedWithCustomError(yieldModule, "TargetNotAllowed");
    });

    it("Should fail with correct error if spender is not allowed", async function () {
      const data = swapProvider.interface.encodeFunctionData("revertEmpty", []);

      await expect(
        yieldModule.connect(owner).swap(tokenIn, 1, swapProviderAddress, otherAddress, data)
      ).to.be.revertedWithCustomError(yieldModule, "SpenderNotAllowed");
    });

    it("Should bubble provider custom error", async function () {
      await (await yieldToken.mint(ownerAddress, 1)).wait();

      const data = swapProvider.interface.encodeFunctionData("revertWithError", []);

      await expect(
        yieldModule.connect(owner).swap(tokenIn, 1, swapProviderAddress, ethers.ZeroAddress, data)
      ).to.be.revertedWithCustomError(swapProvider, "MockRevert");
    });

    it("Should fail with correct error if provider reverts without data", async function () {
      await (await yieldToken.mint(ownerAddress, 1)).wait();

      const data = swapProvider.interface.encodeFunctionData("revertEmpty", []);

      await expect(
        yieldModule.connect(owner).swap(tokenIn, 1, swapProviderAddress, ethers.ZeroAddress, data)
      ).to.be.revertedWithCustomError(yieldModule, "ProviderCallFailed");
    });

    it("Should fail with correct error if tokenIn residue remains after swap", async function () {
      const amountIn = 1000;

      await (await yieldToken.mint(ownerAddress, amountIn)).wait();

      const data = swapProvider.interface.encodeFunctionData("spendPartial", [
        tokenIn,
        amountIn,
        backendAddress,
      ]);

      await expect(
        yieldModule.connect(owner).swap(tokenIn, amountIn, swapProviderAddress, ethers.ZeroAddress, data)
      ).to.be.revertedWithCustomError(yieldModule, "TokenInResidue");
    });

    it("Should execute swap, clear allowance, and emit SwapInitiated event", async function () {
      const amountIn = 2500;

      await (await yieldToken.mint(ownerAddress, amountIn)).wait();

      const sinkBefore = await yieldToken.balanceOf(backendAddress);

      const data = swapProvider.interface.encodeFunctionData("swapExactIn", [
        tokenIn,
        ethers.ZeroAddress,
        amountIn,
        0,
        backendAddress,
      ]);

      const dataHash = ethers.keccak256(data);

      await expect(
        yieldModule.connect(owner).swap(tokenIn, amountIn, swapProviderAddress, ethers.ZeroAddress, data)
      )
        .to.emit(yieldModule, "SwapInitiated")
        .withArgs(tokenIn, amountIn, swapProviderAddress, swapProviderAddress, 0, dataHash);

      expect(await yieldToken.allowance(yieldModuleAddress, swapProviderAddress)).to.equal(0);
      expect(await yieldToken.balanceOf(yieldModuleAddress)).to.equal(0);

      const sinkAfter = await yieldToken.balanceOf(backendAddress);
      expect(sinkAfter - sinkBefore).to.equal(amountIn);
    });

    it("Should pull from protocol when owner balance is insufficient and process service fee", async function () {
      const depositAmount = 100000;
      const accumulatedRevenue = 10000;
      const ownerTopup = 1;
      const amountIn = 2000;

      await (await yieldToken.mint(ownerAddress, depositAmount)).wait();
      await (await yieldModule.connect(owner).enterProtocolByOwner(tokenIn)).wait();

      await (await pool.generateRevenue(yieldModuleAddress, accumulatedRevenue)).wait();

      const feeRate = await processor.serviceFeeRate();
      const serviceFee = Math.floor(accumulatedRevenue * Number(feeRate) / PRECISION);
      const feeReceiver = await processor.feeReceiver();

      await (await yieldToken.mint(ownerAddress, ownerTopup)).wait();

      const pullAmount = amountIn - ownerTopup;

      const data = swapProvider.interface.encodeFunctionData("swapExactIn", [
        tokenIn,
        ethers.ZeroAddress,
        amountIn,
        0,
        backendAddress,
      ]);

      await expect(
        yieldModule.connect(owner).swap(tokenIn, amountIn, swapProviderAddress, ethers.ZeroAddress, data)
      )
        .to.emit(pool, "Withdraw")
        .withArgs(tokenIn, pullAmount, ownerAddress)
        .and.to.emit(protocolToken, "Transfer")
        .withArgs(yieldModuleAddress, feeReceiver, serviceFee)
        .and.to.emit(yieldModule, "FeePaymentProcessed")
        .withArgs(tokenIn, serviceFee, feeReceiver);
    });

    it("Should pull from protocol when owner balance is insufficient and process service fee", async function () {
      const ownerAddress = await owner.getAddress();
      const backendAddress = await backend.getAddress();
      const yieldTokenAddress = await yieldToken.getAddress();

      const depositAmount = 100000n;
      const accumulatedRevenue = 10000n;
      const ownerTopup = 1n;
      const amountIn = 2000n;

      await (await yieldToken.mint(ownerAddress, depositAmount)).wait();
      await (await yieldModule.connect(owner).enterProtocolByOwner(yieldTokenAddress)).wait();
      await (await pool.generateRevenue(yieldModuleAddress, accumulatedRevenue)).wait();

      const feeRate = await processor.serviceFeeRate();
      const serviceFee = (accumulatedRevenue * feeRate) / BigInt(PRECISION);
      const feeReceiver = await processor.feeReceiver();

      await (await yieldToken.mint(ownerAddress, ownerTopup)).wait();

      const pullAmount = amountIn - ownerTopup;

      const data = swapProvider.interface.encodeFunctionData("swapExactIn", [
        yieldTokenAddress,
        ethers.ZeroAddress,
        amountIn,
        0n,
        backendAddress,
      ]);

      const tx = yieldModule
        .connect(owner)
        .swap(yieldTokenAddress, amountIn, swapProviderAddress, ethers.ZeroAddress, data);

      await expect(tx)
        .to.emit(pool, "Withdraw")
        .withArgs(yieldTokenAddress, pullAmount, ownerAddress)
        .and.to.emit(protocolToken, "Transfer")
        .withArgs(yieldModuleAddress, feeReceiver, serviceFee)
        .and.to.emit(yieldModule, "FeePaymentProcessed")
        .withArgs(yieldTokenAddress, serviceFee, feeReceiver);
    });

    it("Should fail with correct error when pull amount exceeds protocol balance minus fee", async function () {
      const ownerAddress = await owner.getAddress();
      const yieldTokenAddress = await yieldToken.getAddress();

      const depositAmount = 1000n;
      const ownerTopup = 1n;
      const amountIn = 2000n;

      await (await yieldToken.mint(ownerAddress, depositAmount)).wait();
      await (await yieldModule.connect(owner).enterProtocolByOwner(yieldTokenAddress)).wait();

      await (await yieldToken.mint(ownerAddress, ownerTopup)).wait();

      const data = swapProvider.interface.encodeFunctionData("revertEmpty", []);

      await expect(
        yieldModule
          .connect(owner)
          .swap(yieldTokenAddress, amountIn, swapProviderAddress, ethers.ZeroAddress, data)
      ).to.be.revertedWithCustomError(yieldModule, "InsufficientFunds");
    });
  });

  describe("swapAndReceive", function () {
    const maxNetworkFee = 12345;

    let yieldModule, yieldModuleAddress;
    let swapProvider, swapProviderAddress;

    let tokenIn;
    let ownerAddress, backendAddress, otherAddress;

    beforeEach(async function () {
      ownerAddress = await owner.getAddress();
      backendAddress = await backend.getAddress();
      otherAddress = await otherAccount.getAddress();

      tokenIn = await yieldToken.getAddress();

      const deployTx = await factory.connect(owner).deployYieldModule(ownerAddress, tokenIn, maxNetworkFee);
      await deployTx.wait();

      const TangemAaveV3YieldModule = await ethers.getContractFactory("TangemAaveV3YieldModule");
      yieldModuleAddress = await factory.calculateYieldModuleAddress(ownerAddress);
      yieldModule = TangemAaveV3YieldModule.attach(yieldModuleAddress);

      const SwapProviderMock = await ethers.getContractFactory("SwapProviderMock");
      swapProvider = await SwapProviderMock.deploy();
      await swapProvider.waitForDeployment();
      swapProviderAddress = await swapProvider.getAddress();

      await (await swapExecutionRegistry.connect(backend).setTargetAllowed(swapProviderAddress, true)).wait();
      await (await swapExecutionRegistry.connect(backend).setSpenderAllowed(swapProviderAddress, true)).wait();

      await (await yieldToken.connect(owner).approve(yieldModuleAddress, ethers.MaxUint256)).wait();
    });

    it("Should fail with correct error if called not by owner", async function () {
      const TestERC20 = await ethers.getContractFactory("TestERC20");
      const outToken = await TestERC20.deploy();
      await outToken.waitForDeployment();

      const tokenOut = await outToken.getAddress();
      const amountIn = 1n;

      const data = swapProvider.interface.encodeFunctionData("swapExactIn", [
        tokenIn,
        tokenOut,
        amountIn,
        0n,
        backendAddress,
      ]);

      await expect(
        yieldModule
          .connect(backend)
          .swapAndReceive(tokenIn, tokenOut, otherAddress, amountIn, swapProviderAddress, ethers.ZeroAddress, data)
      ).to.be.revertedWithCustomError(yieldModule, "OnlyOwner");
    });

    it("Should revert when tokenOut is zero address", async function () {
      const amountIn = 1n;

      const data = swapProvider.interface.encodeFunctionData("swapExactIn", [
        tokenIn,
        ethers.ZeroAddress,
        amountIn,
        0n,
        backendAddress,
      ]);

      await expect(
        yieldModule
          .connect(owner)
          .swapAndReceive(tokenIn, ethers.ZeroAddress, otherAddress, amountIn, swapProviderAddress, ethers.ZeroAddress, data)
      ).to.be.reverted;
    });

    it("Should fail with correct error if tokenIn equals tokenOut", async function () {
      const amountIn = 1n;

      const data = swapProvider.interface.encodeFunctionData("swapExactIn", [
        tokenIn,
        tokenIn,
        amountIn,
        0n,
        backendAddress,
      ]);

      await expect(
        yieldModule
          .connect(owner)
          .swapAndReceive(tokenIn, tokenIn, otherAddress, amountIn, swapProviderAddress, ethers.ZeroAddress, data)
      ).to.be.revertedWithCustomError(yieldModule, "TokenInEqualsTokenOut");
    });

    it("Should fail with correct error if tokenOut is a protocol token", async function () {
      const protocolTokenAddress = await protocolToken.getAddress();
      const amountIn = 1n;

      const data = swapProvider.interface.encodeFunctionData("swapExactIn", [
        tokenIn,
        protocolTokenAddress,
        amountIn,
        0n,
        backendAddress,
      ]);

      await expect(
        yieldModule
          .connect(owner)
          .swapAndReceive(tokenIn, protocolTokenAddress, otherAddress, amountIn, swapProviderAddress, ethers.ZeroAddress, data)
      ).to.be.revertedWithCustomError(yieldModule, "WithdrawingProtocolToken");
    });

    it("Should fail with correct error if swap payout is not received", async function () {
      const TestERC20 = await ethers.getContractFactory("TestERC20");
      const outToken = await TestERC20.deploy();
      await outToken.waitForDeployment();

      const tokenOut = await outToken.getAddress();

      const amountIn = 1000n;

      await (await yieldToken.mint(ownerAddress, amountIn)).wait();

      const data = swapProvider.interface.encodeFunctionData("swapExactIn", [
        tokenIn,
        tokenOut,
        amountIn,
        0n,
        backendAddress,
      ]);

      await expect(
        yieldModule
          .connect(owner)
          .swapAndReceive(tokenIn, tokenOut, otherAddress, amountIn, swapProviderAddress, ethers.ZeroAddress, data)
      ).to.be.revertedWithCustomError(yieldModule, "SwapPayoutNotReceived");
    });

    it("Should revert when tokenOut is not active and receiver is zero address", async function () {
      const TestERC20 = await ethers.getContractFactory("TestERC20");
      const outToken = await TestERC20.deploy();
      await outToken.waitForDeployment();

      const tokenOut = await outToken.getAddress();

      const amountIn = 1000n;
      const amountOut = 500n;

      await (await yieldToken.mint(ownerAddress, amountIn)).wait();
      await (await outToken.mint(swapProviderAddress, amountOut)).wait();

      const data = swapProvider.interface.encodeFunctionData("swapExactIn", [
        tokenIn,
        tokenOut,
        amountIn,
        amountOut,
        backendAddress,
      ]);

      await expect(
        yieldModule
          .connect(owner)
          .swapAndReceive(tokenIn, tokenOut, ethers.ZeroAddress, amountIn, swapProviderAddress, ethers.ZeroAddress, data)
      ).to.be.reverted;
    });

    it("Should fail with correct error when tokenOut is not active and receiver is this contract", async function () {
      const TestERC20 = await ethers.getContractFactory("TestERC20");
      const outToken = await TestERC20.deploy();
      await outToken.waitForDeployment();

      const tokenOut = await outToken.getAddress();

      const amountIn = 1000n;
      const amountOut = 500n;

      await (await yieldToken.mint(ownerAddress, amountIn)).wait();
      await (await outToken.mint(swapProviderAddress, amountOut)).wait();

      const data = swapProvider.interface.encodeFunctionData("swapExactIn", [
        tokenIn,
        tokenOut,
        amountIn,
        amountOut,
        backendAddress,
      ]);

      await expect(
        yieldModule
          .connect(owner)
          .swapAndReceive(tokenIn, tokenOut, yieldModuleAddress, amountIn, swapProviderAddress, ethers.ZeroAddress, data)
      ).to.be.revertedWithCustomError(yieldModule, "SendingToThis");
    });

    it("Should execute swap, clear allowance, transfer tokenOut to receiver, and emit SwapAndReceive events when tokenOut is not active", async function () {
      const TestERC20 = await ethers.getContractFactory("TestERC20");
      const outToken = await TestERC20.deploy();
      await outToken.waitForDeployment();

      const tokenOut = await outToken.getAddress();

      const amountIn = 1000n;
      const amountOut = 500n;

      await (await yieldToken.mint(ownerAddress, amountIn)).wait();
      await (await outToken.mint(swapProviderAddress, amountOut)).wait();

      const outBefore = await outToken.balanceOf(otherAddress);

      const data = swapProvider.interface.encodeFunctionData("swapExactIn", [
        tokenIn,
        tokenOut,
        amountIn,
        amountOut,
        backendAddress,
      ]);
      const dataHash = ethers.keccak256(data);

      await expect(
        yieldModule
          .connect(owner)
          .swapAndReceive(tokenIn, tokenOut, otherAddress, amountIn, swapProviderAddress, ethers.ZeroAddress, data)
      )
        .to.emit(yieldModule, "SwapAndReceiveInitiated")
        .withArgs(tokenIn, tokenOut, otherAddress, amountIn, swapProviderAddress, swapProviderAddress, 0n, dataHash)
        .and.to.emit(outToken, "Transfer")
        .withArgs(yieldModuleAddress, otherAddress, amountOut)
        .and.to.emit(yieldModule, "SwapAndReceiveCompleted")
        .withArgs(tokenOut, otherAddress, amountOut, false);

      expect(await yieldToken.allowance(yieldModuleAddress, swapProviderAddress)).to.equal(0n);
      expect(await yieldToken.balanceOf(yieldModuleAddress)).to.equal(0n);

      const outAfter = await outToken.balanceOf(otherAddress);
      expect(outAfter - outBefore).to.equal(amountOut);
    });

    it("Should deposit tokenOut to protocol and emit FeePaymentFailed when tokenOut is active and fee is zero", async function () {
      const TestERC20 = await ethers.getContractFactory("TestERC20");
      const outToken = await TestERC20.deploy();
      await outToken.waitForDeployment();

      const tokenOut = await outToken.getAddress();

      await (await yieldModule.connect(owner).initYieldToken(tokenOut, 0)).wait();

      const amountIn = 1000n;
      const amountOut = 500n;

      await (await yieldToken.mint(ownerAddress, amountIn)).wait();
      await (await outToken.mint(swapProviderAddress, amountOut)).wait();

      const data = swapProvider.interface.encodeFunctionData("swapExactIn", [
        tokenIn,
        tokenOut,
        amountIn,
        amountOut,
        backendAddress,
      ]);

      await expect(
        yieldModule
          .connect(owner)
          .swapAndReceive(tokenIn, tokenOut, otherAddress, amountIn, swapProviderAddress, ethers.ZeroAddress, data)
      )
        .to.emit(pool, "Supply")
        .withArgs(tokenOut, amountOut, yieldModuleAddress, 0)
        .and.to.emit(yieldModule, "FeePaymentFailed")
        .withArgs(tokenOut, 0n)
        .and.to.emit(yieldModule, "SwapAndReceiveCompleted")
        .withArgs(tokenOut, otherAddress, amountOut, true);
    });

    it("Should deposit tokenOut to protocol and process service fee when tokenOut is active and revenue exists", async function () {
      const TestERC20 = await ethers.getContractFactory("TestERC20");
      const outToken = await TestERC20.deploy();
      await outToken.waitForDeployment();

      const tokenOut = await outToken.getAddress();

      await (await yieldModule.connect(owner).initYieldToken(tokenOut, 0)).wait();

      const seed = 100000n;
      await (await outToken.mint(ownerAddress, seed)).wait();
      await (await outToken.connect(owner).approve(yieldModuleAddress, ethers.MaxUint256)).wait();
      await (await yieldModule.connect(owner).enterProtocolByOwner(tokenOut)).wait();

      const accumulatedRevenue = 10000n;
      await (await pool.generateRevenue(yieldModuleAddress, accumulatedRevenue)).wait();

      const feeRate = await processor.serviceFeeRate();
      const expectedFeeOut = (accumulatedRevenue * feeRate) / BigInt(PRECISION);
      const feeReceiver = await processor.feeReceiver();

      const amountIn = 1000n;
      const amountOut = 500n;

      await (await yieldToken.mint(ownerAddress, amountIn)).wait();
      await (await outToken.mint(swapProviderAddress, amountOut)).wait();

      const data = swapProvider.interface.encodeFunctionData("swapExactIn", [
        tokenIn,
        tokenOut,
        amountIn,
        amountOut,
        backendAddress,
      ]);

      await expect(
        yieldModule
          .connect(owner)
          .swapAndReceive(tokenIn, tokenOut, otherAddress, amountIn, swapProviderAddress, ethers.ZeroAddress, data)
      )
        .to.emit(pool, "Supply")
        .withArgs(tokenOut, amountOut, yieldModuleAddress, 0)
        .and.to.emit(protocolToken, "Transfer")
        .withArgs(yieldModuleAddress, feeReceiver, expectedFeeOut)
        .and.to.emit(yieldModule, "FeePaymentProcessed")
        .withArgs(tokenOut, expectedFeeOut, feeReceiver)
        .and.to.emit(yieldModule, "SwapAndReceiveCompleted")
        .withArgs(tokenOut, otherAddress, amountOut, true);
    });
  });

  describe("withdrawNativeAll", function () {
    const maxNetworkFee = 12345;

    let yieldModule, yieldModuleAddress;
    let ownerAddress, backendAddress;
    let tokenIn;

    beforeEach(async function () {
      ownerAddress = await owner.getAddress();
      backendAddress = await backend.getAddress();
      tokenIn = await yieldToken.getAddress();

      const deployTx = await factory.connect(owner).deployYieldModule(ownerAddress, tokenIn, maxNetworkFee);
      await deployTx.wait();

      const TangemAaveV3YieldModule = await ethers.getContractFactory("TangemAaveV3YieldModule");
      yieldModuleAddress = await factory.calculateYieldModuleAddress(ownerAddress);
      yieldModule = TangemAaveV3YieldModule.attach(yieldModuleAddress);
    });

    it("Should emit WithdrawNativeProcessed with zero amount when balance is zero", async function () {
      await expect(yieldModule.connect(owner).withdrawNativeAll(backendAddress))
        .to.emit(yieldModule, "WithdrawNativeProcessed")
        .withArgs(backendAddress, 0n);
    });

    it("Should transfer native balance and emit WithdrawNativeProcessed when balance is non-zero", async function () {
      const value = 1000000000000000n;

      await (await owner.sendTransaction({ to: yieldModuleAddress, value })).wait();

      const tx = yieldModule.connect(owner).withdrawNativeAll(backendAddress);

      await expect(tx).to.changeEtherBalances([yieldModuleAddress, backendAddress], [-value, value]);
      await expect(tx).to.emit(yieldModule, "WithdrawNativeProcessed").withArgs(backendAddress, value);
    });

    it("Should fail with correct error when native transfer fails", async function () {
      const value = 1000000000000000n;
      const badReceiver = await swapExecutionRegistry.getAddress();

      await (await owner.sendTransaction({ to: yieldModuleAddress, value })).wait();

      await expect(yieldModule.connect(owner).withdrawNativeAll(badReceiver))
        .to.be.revertedWithCustomError(yieldModule, "NativeTransferFailed");
    });

    it("Should revert when receiver is zero address", async function () {
      await expect(yieldModule.connect(owner).withdrawNativeAll(ethers.ZeroAddress)).to.be.reverted;
    });

    it("Should fail with correct error if called not by owner", async function () {
      await expect(yieldModule.connect(backend).withdrawNativeAll(backendAddress))
        .to.be.revertedWithCustomError(yieldModule, "OnlyOwner");
    });
  });
});
