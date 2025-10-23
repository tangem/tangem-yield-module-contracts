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

task("deploy-module", "Deploys yield module")
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

    const yieldModuleAddress = await factory.yieldModules(ownerAddress);
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
  .addParam("factory", "The address of the yield module factory")
  .addParam("owner", "The address of the yield module's owner")
  .addParam("token", "The address of the yield token")
  .addParam("maxFee", "The address of the yield token")
  .setAction(async (taskArgs) => {
    await hre.run('compile');

    const processorAddress = taskArgs.processor;
    const factoryAddress = taskArgs.factory;
    const ownerAddress = taskArgs.owner;
    const yieldTokenAddress = taskArgs.token;
    const maxFee = taskArgs.maxFee;

    const TangemYieldModuleFactory = await ethers.getContractFactory("TangemYieldModuleFactory");
    const factory = TangemYieldModuleFactory.attach(factoryAddress);
    
    const yieldModuleAddress = factory.yieldModules(ownerAddress);

    const TangemYieldProcessor = await ethers.getContractFactory("TangemYieldProcessor");
    const processor = TangemYieldProcessor.attach(processorAddress);
    
    const enterTx = await processor.enterProtocol(yieldModuleAddress, yieldTokenAddress, maxFee); // , { gasLimit: 3000000 });
    await enterTx.wait();

    console.log("Protocol entered");
  });

task("grant-backend-roles", "Withdraws user funds")
  .addParam("processor", "The address of the yield processor")
  .addParam("to", "The address of the account to grant roles to")
  .setAction(async (taskArgs) => {
    await hre.run('compile');

    const processorAddress = taskArgs.processor;
    const to = taskArgs.to;

    const TangemYieldProcessor = await ethers.getContractFactory("TangemYieldProcessor");
    const processor = TangemYieldProcessor.attach(processorAddress);
    
    const protocolEntererRole = ethers.id("PROTOCOL_ENTERER_ROLE")
    const grantTx1 = await processor.grantRole(protocolEntererRole, to);
    await grantTx1.wait();

    const serviceFeeCollectorRole = ethers.id("SERVICE_FEE_COLLECTOR_ROLE")
    const grantTx2 = await processor.grantRole(serviceFeeCollectorRole, to);
    await grantTx2.wait();

    console.log("Backend roles granted");
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
    polygon: {
      url: "https://rpc-mainnet.matic.quiknode.pro/",
      accounts: ACCOUNTS
    },
    sepolia: {
      url: "https://gateway.tenderly.co/public/sepolia",
      accounts: ACCOUNTS
    },
    arbitrum_sepolia: {
      url: "https://arbitrum-sepolia.drpc.org",
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
