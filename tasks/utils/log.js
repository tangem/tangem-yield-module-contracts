const RESET = "\x1b[0m";
const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";
const RED = "\x1b[31m";
const MAGENTA = "\x1b[35m";

function prefix(functionName, networkName, color) {
  const network = networkName ? `${MAGENTA}[${networkName}]${RESET}` : "";

  return `${network}${color}[${functionName}]${RESET}`;
}

function log(message, functionName, networkName) {
  console.log(prefix(functionName, networkName, GREEN), message);
}

function warn(message, functionName, networkName) {
  console.log(prefix(functionName, networkName, YELLOW), message);
}

function err(message, functionName, networkName) {
  console.log(`${prefix(functionName, networkName, RED)}${RED} ERROR:${RESET}`, message);
}

/** `0x1234…cdef` — for tx hashes, which are rarely copied by hand. */
function shorten(value) {
  const text = String(value);

  return text.length > 14 ? `${text.slice(0, 6)}…${text.slice(-4)}` : text;
}

module.exports = { err, log, shorten, warn };
