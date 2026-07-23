// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { YieldModuleLiquidUpgradeable } from "../core/YieldModuleLiquidUpgradeable.sol";
import { IAToken } from "../interfaces/IAToken.sol";
import { MerklIncentives } from "../merkl/MerklIncentives.sol";

contract TangemAaveV3YieldModule is YieldModuleLiquidUpgradeable, MerklIncentives {
    using SafeERC20 for IERC20;

    IPool public immutable pool;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address pool_,
        address distributor_,
        address yieldProcessor_,
        address factory_,
        address trustedForwarder_,
        address swapExecutionRegistry_
    )
        MerklIncentives(distributor_)
        YieldModuleLiquidUpgradeable(
            yieldProcessor_, factory_, trustedForwarder_, swapExecutionRegistry_
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

    function _pullFromProtocolToOwner(
        address yieldToken,
        uint amount
    ) internal override returns (uint) {
        return pool.withdraw(yieldToken, amount, owner);
    }

    function _pullFromProtocolToModule(
        address yieldToken,
        uint amount
    ) internal override returns (uint) {
        return pool.withdraw(yieldToken, amount, address(this));
    }

    function _initProtocolToken(address yieldToken) internal virtual override returns (address) {
        return _getProtocolToken(yieldToken);
    }

    function _getYieldTokenByProtocolToken(address protocolToken)
        internal
        view
        virtual
        override
        returns (address)
    {
        address underlying = IAToken(protocolToken).UNDERLYING_ASSET_ADDRESS();
        address aToken = _getProtocolToken(underlying);

        return protocolToken == aToken ? underlying : address(0);
    }

    function _getProtocolToken(address yieldToken)
        internal
        view
        virtual
        override
        returns (address)
    {
        return IPool(pool).getReserveData(yieldToken).aTokenAddress;
    }
}
