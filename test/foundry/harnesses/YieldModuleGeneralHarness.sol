// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { YieldModuleHarness } from "./YieldModuleHarness.sol";
import { YieldModuleBase } from "contracts/core/YieldModuleBase.sol";
import { MerklIncentives } from "contracts/extensions/MerklIncentives.sol";
import { SwapExecution } from "contracts/extensions/SwapExecution.sol";
import { GeneralPoolMock } from "contracts/test/GeneralPoolMock.sol";

contract YieldModuleGeneralHarness is YieldModuleHarness {
    using SafeERC20 for IERC20;

    GeneralPoolMock public immutable pool;

    constructor(
        address pool_,
        address distributor_,
        address yieldProcessor_,
        address factory_,
        address trustedForwarder_,
        address swapExecutionRegistry_
    )
        MerklIncentives(distributor_)
        SwapExecution(swapExecutionRegistry_)
        YieldModuleBase(yieldProcessor_, factory_, trustedForwarder_)
    {
        pool = GeneralPoolMock(pool_);

        _disableInitializers();
    }

    function initialize(address _owner) external initializer {
        __YieldModule_init(_owner);
    }

    function _initProtocolToken(address yieldToken) internal override returns (address) {
        return pool.initProtocolToken(yieldToken);
    }

    function _getProtocolToken(address yieldToken) internal view override returns (address) {
        return address(pool.protocolTokens(yieldToken));
    }

    function _tryResolveYieldToken(address protocolToken) internal view override returns (address) {
        return pool.yieldTokensByProtocolToken(protocolToken);
    }

    function _pushToProtocol(address yieldToken, uint amount) internal override {
        IERC20(yieldToken).forceApprove(address(pool), amount);
        pool.deposit(yieldToken, amount);
    }

    function _pullFromProtocolToOwner(address yieldToken, uint amount) internal override returns (uint) {
        return pool.withdraw(yieldToken, amount, owner);
    }

    function _pullFromProtocolToModule(address yieldToken, uint amount) internal override returns (uint) {
        return pool.withdraw(yieldToken, amount, address(this));
    }
}
