// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { MerklIncentives } from "contracts/merkl/MerklIncentives.sol";
import { YieldModuleHarness } from "./YieldModuleHarness.sol";
import { YieldModuleLiquidUpgradeable } from "contracts/core/YieldModuleLiquidUpgradeable.sol";
import { TestERC20 } from "contracts/test/TestERC20.sol";

/// Concrete protocol-agnostic harness. Uses TestERC20 as a fake "pool": each yieldToken gets
/// its own TestERC20 protocolToken (mint/burn instead of real deposit/withdraw).
/// Used by MerklIncentives and other protocol-agnostic test suites.
contract YieldModuleGeneralHarness is YieldModuleHarness {
    mapping(address => TestERC20) internal _protocolTokens;
    mapping(address => address) internal _yieldTokensByProtocol;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
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
        _disableInitializers();
    }

    function initialize(address _owner) external initializer {
        __YieldModule_init(_owner);
    }

    /* HOOK IMPLEMENTATIONS — fake pool via TestERC20 mint/burn */

    function _initProtocolToken(address yieldToken) internal override returns (address) {
        TestERC20 pt = new TestERC20("TestProtocolToken", "ptTST", 18);
        pt.forceBurn(address(this), pt.balanceOf(address(this)));
        _protocolTokens[yieldToken] = pt;
        _yieldTokensByProtocol[address(pt)] = yieldToken;
        return address(pt);
    }

    function _getProtocolToken(address yieldToken) internal view override returns (address) {
        return address(_protocolTokens[yieldToken]);
    }

    function _getYieldTokenByProtocolToken(address protocolToken)
        internal
        view
        override
        returns (address)
    {
        return _yieldTokensByProtocol[protocolToken];
    }

    function _pushToProtocol(address yieldToken, uint amount) internal override {
        _protocolTokens[yieldToken].mint(address(this), amount);
    }

    function _pullFromProtocolToOwner(address yieldToken, uint amount)
        internal
        override
        returns (uint)
    {
        if (amount == type(uint).max) {
            amount = _protocolTokens[yieldToken].balanceOf(address(this));
        }
        _protocolTokens[yieldToken].forceBurn(address(this), amount);
        IERC20(yieldToken).transfer(owner, amount);
        return amount;
    }

    function _pullFromProtocolToModule(address yieldToken, uint amount)
        internal
        override
        returns (uint)
    {
        if (amount == type(uint).max) {
            amount = _protocolTokens[yieldToken].balanceOf(address(this));
        }
        _protocolTokens[yieldToken].forceBurn(address(this), amount);
        return amount;
    }

    /* REVENUE SIMULATION */

    /// Mints protocolToken to track _protocolBalance. yieldToken minting is handled by
    /// YieldModuleBase._generateRevenue (which has backend access to mint yieldToken).
    function generateRevenue(address yieldToken, address account, uint amount) external {
        _protocolTokens[yieldToken].mint(account, amount);
    }
}