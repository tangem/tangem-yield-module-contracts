const { log } = require("./log");

/**
 * Awaits the transaction, waits for its receipt and logs it as [network][functionName].
 * `message` describes the arguments and is optional when the function name says enough.
 */
async function send(hre, functionName, txPromise, message = "") {
  const tx = await txPromise;
  const receipt = await tx.wait();

  log(`${message}${message ? " " : ""}(tx ${tx.hash})`, functionName, hre.network.name);

  return receipt;
}

module.exports = { send };
