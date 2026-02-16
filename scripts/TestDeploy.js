const { ethers } = require("hardhat");

async function deployTestSetup() {
    const msgSender = (await hre.ethers.getSigners())[0].address

    const TestERC20 = await ethers.getContractFactory("TestERC20");
    const yieldToken = await TestERC20.deploy();
    await yieldToken.waitForDeployment();

    const TangemERC2771Forwarder = await ethers.getContractFactory("TangemERC2771Forwarder");
    const forwarder = await TangemERC2771Forwarder.deploy();
    await forwarder.waitForDeployment();

    const AaveV3PoolMock = await ethers.getContractFactory("AaveV3PoolMock");
    const pool = await AaveV3PoolMock.deploy();
    await pool.waitForDeployment();

    const mintTx = await yieldToken.mint(pool, 1000000000);
    await mintTx.wait();

    const TangemYieldProcessor = await ethers.getContractFactory("TangemYieldProcessor");
    const processor = await TangemYieldProcessor.deploy(msgSender, 100);
    await processor.waitForDeployment();

    const protocolEntererRole = ethers.id("PROTOCOL_ENTERER_ROLE")
    const grantTx1 = await processor.grantRole(protocolEntererRole, msgSender);
    await grantTx1.wait();

    const protocolExiterRole = ethers.id("PROTOCOL_EXITER_ROLE")
    const grantTx2 = await processor.grantRole(protocolExiterRole, msgSender);
    await grantTx2.wait();

    const serviceFeeCollectorRole = ethers.id("SERVICE_FEE_COLLECTOR_ROLE")
    const grantTx3 = await processor.grantRole(serviceFeeCollectorRole, msgSender);
    await grantTx3.wait();

    const propertySetterRole = ethers.id("PROPERTY_SETTER_ROLE")
    const grantTx4 = await processor.grantRole(propertySetterRole, msgSender);
    await grantTx4.wait();

    const pauserRole = ethers.id("PAUSER_ROLE")
    const grantTx5 = await processor.grantRole(pauserRole, msgSender);
    await grantTx5.wait();

    const TangemYieldModuleFactory = await ethers.getContractFactory("TangemYieldModuleFactory");
    const factory = await TangemYieldModuleFactory.deploy();
    await factory.waitForDeployment();

    const SwapExecutionRegistry = await ethers.getContractFactory("SwapExecutionRegistry");
    const swapExecutionRegistry = await SwapExecutionRegistry.deploy(msgSender);
    await swapExecutionRegistry.waitForDeployment();

    const AaveV3YieldModule = await ethers.getContractFactory("TangemAaveV3YieldModule");
    const moduleImplementation = await AaveV3YieldModule.deploy(pool, processor, factory, forwarder, swapExecutionRegistry);
    await moduleImplementation.waitForDeployment();

    const implementationSetterRole = ethers.id("IMPLEMENTATION_SETTER_ROLE")
    const grantTx6 = await factory.grantRole(implementationSetterRole, msgSender);
    await grantTx6.wait();

    const grantTx7 = await factory.grantRole(pauserRole, msgSender);
    await grantTx7.wait();

    const setTx = await factory.setImplementation(moduleImplementation);
    await setTx.wait();

    const unpauseTx = await factory.unpause();
    await unpauseTx.wait();

    return { yieldToken, factory, processor, pool, forwarder, swapExecutionRegistry };
}

module.exports = { deployTestSetup };