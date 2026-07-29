// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { YieldModuleBase } from "contracts/core/YieldModuleBase.sol";
import { YieldModuleLiquidUpgradeable } from "contracts/core/YieldModuleLiquidUpgradeable.sol";
import { SwapExecution } from "contracts/extensions/SwapExecution.sol";
import { IAToken } from "contracts/interfaces/IAToken.sol";

contract TangemAaveV3YieldModule is YieldModuleLiquidUpgradeable, SwapExecution {
    using SafeERC20 for IERC20;

    IPool public immutable pool;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address pool_,
        address yieldProcessor_,
        address factory_,
        address trustedForwarder_,
        address swapExecutionRegistry_
    ) SwapExecution(swapExecutionRegistry_) YieldModuleBase(yieldProcessor_, factory_, trustedForwarder_) {
        pool = IPool(pool_);

        _disableInitializers();
    }

    function initialize(address _owner) external initializer {
        __YieldModule_init(_owner);
    }

    function _pushToProtocol(address yieldToken, uint amount) internal override {
        IERC20(yieldToken).forceApprove(address(pool), amount);
        pool.supply(yieldToken, amount, address(this), 0);
    }

    function _pullFromProtocolToOwner(address yieldToken, uint amount) internal override returns (uint) {
        return pool.withdraw(yieldToken, amount, owner);
    }

    function _pullFromProtocolToModule(address yieldToken, uint amount) internal override returns (uint) {
        return pool.withdraw(yieldToken, amount, address(this));
    }

    function _initProtocolToken(address yieldToken) internal virtual override returns (address) {
        return IPool(pool).getReserveData(yieldToken).aTokenAddress;
    }
}
