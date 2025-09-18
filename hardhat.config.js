require("@nomicfoundation/hardhat-toolbox");
require("hardhat-abi-exporter");
require("@solidstate/hardhat-bytecode-exporter");
require("dotenv").config();

const MNEMONIC = process.env.MNEMONIC;
const ACCOUNTS = MNEMONIC ? { "mnemonic": MNEMONIC, "initialIndex": 0 } : "remote";

task("deploy-base", "Deploys contracts for testing")
  .addParam("pool", "The address of the Aave pool")
  .setAction(async (taskArgs) => {
    await hre.run('compile');

    const msgSender = (await hre.ethers.getSigners())[0].address

    const pool = taskArgs.pool;

    const TangemERC2771Forwarder = await ethers.getContractFactory("TangemERC2771Forwarder");
    const forwarder = await TangemERC2771Forwarder.deploy();
    await forwarder.waitForDeployment();

    const TangemYieldProcessor = await ethers.getContractFactory("TangemYieldProcessor");
    const processor = await TangemYieldProcessor.deploy(msgSender, 100);
    await processor.waitForDeployment();

    console.log("TangemYieldProcessor deployed to: ", await processor.getAddress());

    const protocolEntererRole = ethers.id("PROTOCOL_ENTERER_ROLE")
    const grantTx1 = await processor.grantRole(protocolEntererRole, msgSender);
    await grantTx1.wait();

    const protocolExiterRole = ethers.id("PROTOCOL_EXITER_ROLE")
    const grantTx2 = await processor.grantRole(protocolExiterRole, msgSender);
    await grantTx2.wait();

    const serviceFeeCollectorRole = ethers.id("SERVICE_FEE_COLLECTOR_ROLE")
    const grantTx3 = await processor.grantRole(serviceFeeCollectorRole, msgSender);
    await grantTx3.wait();

    const TangemYieldModuleFactory = await ethers.getContractFactory("TangemYieldModuleFactory");
    const factory = await TangemYieldModuleFactory.deploy();
    await factory.waitForDeployment();

    const AaveV3YieldModule = await ethers.getContractFactory("TangemAaveV3YieldModule");
    const moduleImplementation = await AaveV3YieldModule.deploy(pool, processor, factory, forwarder);
    await moduleImplementation.waitForDeployment();

    const implementationSetterRole = ethers.id("IMPLEMENTATION_SETTER_ROLE")
    const grantTx4 = await factory.grantRole(implementationSetterRole, msgSender);
    await grantTx4.wait();

    const pauserRole = ethers.id("PAUSER_ROLE")
    const grantTx5 = await factory.grantRole(pauserRole, msgSender);
    await grantTx5.wait();

    const setTx = await factory.setImplementation(moduleImplementation);
    await setTx.wait();

    const unpauseTx = await factory.unpause();
    await unpauseTx.wait();

    console.log("TangemYieldModuleFactory deployed to: ", await factory.getAddress());
  });

task("deploy-account", "Deploys yield module")
  .addParam("factory", "The address of the yield module factory")
  .addParam("token", "The address of the yield token")
  .setAction(async (taskArgs) => {
    await hre.run('compile');

    const msgSender = (await hre.ethers.getSigners())[0].address

    const factoryAddress = taskArgs.factory;
    const yieldTokenAddress = taskArgs.token;
    const ownerAddress = msgSender;

    const TangemYieldModuleFactory = await ethers.getContractFactory("TangemYieldModuleFactory");
    const factory = TangemYieldModuleFactory.attach(factoryAddress)
    
    const deployTx = await factory.deployYieldModule(ownerAddress, yieldTokenAddress, 100);
    await deployTx.wait();

    const yieldModuleAddress = await factory.calculateYieldModuleAddress(ownerAddress);
    const AaveV3YieldModule = await ethers.getContractFactory("TangemAaveV3YieldModule");
    const yieldModule = AaveV3YieldModule.attach(yieldModuleAddress);

    console.log("TangemYieldModule deployed to: " + yieldModuleAddress);

    const TestERC20 = await ethers.getContractFactory("TestERC20");
    const yieldToken = TestERC20.attach(yieldTokenAddress);

    const approveTx = await yieldToken.approve(yieldModule, hre.ethers.MaxUint256);
    await approveTx.wait();

    console.log("Yield token approval given");
  });

task("enter-protocol", "Enters yield protocol")
  .addParam("processor", "The address of the yield processor")
  .addParam("account", "The address of the yield module")
  .addParam("token", "The address of the yield token")
  .setAction(async (taskArgs) => {
    await hre.run('compile');

    const processorAddress = taskArgs.processor;
    const yieldModuleAddress = taskArgs.account;
    const yieldTokenAddress = taskArgs.token;

    const TangemYieldProcessor = await ethers.getContractFactory("TangemYieldProcessor");
    const processor = TangemYieldProcessor.attach(processorAddress);
    
    const enterTx = await processor.enterProtocol(yieldModuleAddress, yieldTokenAddress, 100); // , { gasLimit: 3000000 });
    await enterTx.wait();

    console.log("Protocol entered");
  });

task("withdraw-self", "Withdraws user funds")
  .addParam("module", "The address of the yield module")
  .addParam("amount", "Amount to withdraw")
  .addParam("token", "The address of the yield token")
  .setAction(async (taskArgs) => {
    await hre.run('compile');

    const msgSender = (await hre.ethers.getSigners())[0].address

    const yieldModuleAddress = taskArgs.account;
    const amount = taskArgs.amount;
    const yieldTokenAddress = taskArgs.token;

    const TangemAaveV3YieldModule = await ethers.getContractFactory("TangemAaveV3YieldModule");
    const yieldModule = TangemAaveV3YieldModule.attach(yieldModuleAddress);
    
    const withdrawTx = await yieldModule.withdraw(yieldTokenAddress, msgSender, amount); // , { gasLimit: 3000000 });
    await withdrawTx.wait();

    console.log("Funds withdrawn");
  });

task("get-module-address", "Withdraws user funds")
  .addParam("owner", "The address of the yield module's owner")
  .addParam("factory", "The address of the yield module factory")
  .setAction(async (taskArgs) => {
    const factoryAddress = taskArgs.factory;
    const ownerAddress = taskArgs.owner;

    const TangemYieldModuleFactory = await ethers.getContractFactory("TangemYieldModuleFactory");
    const factory = TangemYieldModuleFactory.attach(factoryAddress);

    const moduleAddress = await factory.calculateYieldModuleAddress(ownerAddress);

    console.log("Owner's yield module address - " + moduleAddress);
  });

module.exports = {
  solidity: {
    version: "0.8.29",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  abiExporter: {
    path: "./abi",
    clear: true,
    flat: true
  },
  bytecodeExporter: {
    path: "./bin",
    runOnCompile: true,
    clear: true,
    flat: true
  },
  networks: {
    mumbai: {
      url: "https://polygon-mumbai.g.alchemy.com/v2/_1qqjXgBC_IikaXChnna8KTcV2eMMIQG",
      accounts: ACCOUNTS
    },
    polygon: {
      url: "https://rpc-mainnet.matic.quiknode.pro/",
      accounts: ACCOUNTS
    },
    sepolia: {
      url: "https://gateway.tenderly.co/public/sepolia",
      accounts: ACCOUNTS
    },
    hardhat: {
      allowUnlimitedContractSize: false
    }
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS == "true"
  }
};
