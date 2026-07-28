const { task } = require("hardhat/config");
const { compile, getContract, log } = require("./utils");

async function getEffectiveBalance(hre, args) {
  const yieldModule = await getContract(hre, "TangemAaveV3YieldModule", args.module);
  const effectiveBalance = await yieldModule.effectiveBalance(args.token);

  log(effectiveBalance, "effectiveBalance", hre.network.name);

  return effectiveBalance;
}

task("get-effective-balance", "Reads the effective balance of a yield module")
  .addParam("module", "The address of the yield module")
  .addParam("token", "The address of the yield token")
  .setAction(async (args, hre) => {
    await compile(hre);
    await getEffectiveBalance(hre, args);
  });

module.exports = { getEffectiveBalance };
