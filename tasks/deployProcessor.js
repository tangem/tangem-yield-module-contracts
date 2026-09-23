const { task } = require("hardhat/config");
const { compile, deployContract } = require("./utils");

const DEFAULT_FEE_RECEIVER = "0x37E7e93093AE3A8AAEf4A0D41DBd9c037508eB60";
const DEFAULT_SERVICE_FEE_RATE = 1500;

async function deployProcessor(hre, args = {}) {
  const feeReceiver = args.feeReceiver || DEFAULT_FEE_RECEIVER;
  const serviceFeeRate = args.serviceFeeRate ?? DEFAULT_SERVICE_FEE_RATE;

  return deployContract(hre, "TangemYieldProcessor", [feeReceiver, serviceFeeRate], { verify: true });
}

task("deploy-processor", "Deploys a new TangemYieldProcessor")
  .addOptionalParam("feeReceiver", `The address collecting service fees (defaults to ${DEFAULT_FEE_RECEIVER})`)
  .addOptionalParam("serviceFeeRate", `The service fee rate in bps (defaults to ${DEFAULT_SERVICE_FEE_RATE})`)
  .setAction(async (args, hre) => {
    await compile(hre);
    await deployProcessor(hre, args);
  });

module.exports = { DEFAULT_FEE_RECEIVER, DEFAULT_SERVICE_FEE_RATE, deployProcessor };
