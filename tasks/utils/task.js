const { err } = require("./log");

/** Wraps a task action: a failure is logged as [functionName] ERROR and sets exit code 1. */
function withErrorLog(functionName, action) {
  return async (args, hre) => {
    try {
      await action(args, hre);
    } catch (error) {
      err(error.message, functionName);

      // AggregateError's own message omits the underlying causes.
      for (const cause of error.errors ?? []) {
        err(cause.message, functionName);
      }

      process.exitCode = 1;
    }
  };
}

module.exports = { withErrorLog };
