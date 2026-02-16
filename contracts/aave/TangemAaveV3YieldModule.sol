// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "../core/YieldModuleLiquidUpgradeable.sol";

contract TangemAaveV3YieldModule is YieldModuleLiquidUpgradeable {
    using SafeERC20 for IERC20;

    IPool public immutable pool;
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address pool_,
        address yieldProcessor_,
        address factory_,
        address trustedForwarder_,
        address swapExecutionRegistry_
    )
        YieldModuleLiquidUpgradeable(
            yieldProcessor_,
            factory_,
            trustedForwarder_,
            swapExecutionRegistry_
        )
    {
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

    function _pullFromProtocol(address yieldToken, uint amount) internal override returns (uint) {
        return pool.withdraw(yieldToken, amount, owner);
    }

    function _initProtocolToken(address yieldToken) internal virtual override returns (address) {
        return IPool(pool).getReserveData(yieldToken).aTokenAddress;
    }
}