const { task } = require("hardhat/config");
const { compile, getContract, getSigner, log, send } = require("./utils");

const DEFAULT_MAX_NETWORK_FEE = 100;
const ERC20_APPROVE_ABI = ["function approve(address spender, uint256 value) returns (bool)"];

async function deployModule(hre, args) {
  const owner = (await getSigner(hre)).address;
  const maxNetworkFee = args.maxFee ?? DEFAULT_MAX_NETWORK_FEE;

  const factory = await getContract(hre, "TangemYieldModuleFactory", args.factory);

  await send(hre, "deployYieldModule", factory.deployYieldModule(owner, args.token, maxNetworkFee), owner);

  const yieldModuleAddress = await factory.yieldModules(owner);
  log(`deployed to ${yieldModuleAddress}`, "TangemYieldModule", hre.network.name);

  const yieldToken = await hre.ethers.getContractAt(ERC20_APPROVE_ABI, args.token);
  await send(hre, "approve", yieldToken.approve(yieldModuleAddress, hre.ethers.MaxUint256), `max to ${yieldModuleAddress}`);

  return yieldModuleAddress;
}

task("deploy-module", "Deploys a yield module for the deployer")
  .addParam("factory", "The address of the yield module factory")
  .addParam("token", "The address of the yield token")
  .addOptionalParam("maxFee", `The maximum network fee (defaults to ${DEFAULT_MAX_NETWORK_FEE})`)
  .setAction(async (args, hre) => {
    await compile(hre);
    await deployModule(hre, args);
  });

module.exports = { deployModule };
