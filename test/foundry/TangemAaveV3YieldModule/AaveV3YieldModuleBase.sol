// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { YieldModuleBase } from "test/foundry/YieldModuleBase.sol";
import { TangemAaveV3YieldModuleHarness } from "test/foundry/harnesses/TangemAaveV3YieldModuleHarness.sol";

import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";
import { PRECISION } from "contracts/resources/Constants.sol";
import { AaveV3PoolMock } from "contracts/test/AaveV3PoolMock.sol";
import { TestERC20 } from "contracts/test/TestERC20.sol";

abstract contract AaveV3YieldModuleBase is YieldModuleBase {
    uint internal constant INITIAL_MODULE_BALANCE = 50_000e6;
    uint internal constant TOTAL_ENTER_AMOUNT = INITIAL_OWNER_BALANCE + INITIAL_MODULE_BALANCE;
    uint internal constant FRESH_OWNER_BALANCE = 50_000e6;

    TestERC20 public protocolToken;
    AaveV3PoolMock public pool;
    TangemAaveV3YieldModuleHarness public implementation;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(backend);

        pool = new AaveV3PoolMock();
        yieldToken.mint(address(pool), POOL_LIQUIDITY);

        implementation = new TangemAaveV3YieldModuleHarness(
            address(pool),
            address(merklDistributor),
            address(processor),
            address(factory),
            address(forwarder),
            address(swapExecutionRegistry)
        );

        factory.setImplementation(address(implementation));
        factory.unpause();

        vm.stopPrank();

        protocolToken = pool.aToken();

        _labelAaveAddresses();
    }

    function _labelAaveAddresses() internal {
        vm.label(address(protocolToken), "protocolToken");
        vm.label(address(pool), "aavePoolMock");
        vm.label(address(implementation), "implementation");
    }

    /* FIXTURE HELPERS */

    function _deployYieldModule(
        address moduleOwner,
        address yieldTokenAddr,
        uint240 maxNetworkFee
    ) internal returns (TangemAaveV3YieldModuleHarness yieldModule) {
        vm.prank(moduleOwner);
        factory.deployYieldModule(moduleOwner, yieldTokenAddr, maxNetworkFee);

        yieldModule = TangemAaveV3YieldModuleHarness(
            payable(factory.calculateYieldModuleAddress(moduleOwner))
        );
        vm.label(address(yieldModule), "yieldModule");
    }

    function _deployYieldModuleWithFunds(
        address moduleOwner,
        uint ownerBalance
    ) internal returns (TangemAaveV3YieldModuleHarness yieldModule) {
        yieldModule = _deployYieldModule(moduleOwner, address(yieldToken), DEFAULT_MAX_NETWORK_FEE);

        _mintYieldToken(moduleOwner, ownerBalance);

        vm.prank(moduleOwner);
        yieldToken.approve(address(yieldModule), type(uint).max);
    }

    function _deployEnteredRevenueModule(address moduleOwner)
        internal
        returns (TangemAaveV3YieldModuleHarness yieldModule)
    {
        yieldModule = _deployYieldModuleWithFunds(moduleOwner, INITIAL_OWNER_BALANCE);
        _enterViaProcessor(yieldModule, 0);
        _generateRevenue(address(yieldModule), ACCUMULATED_REVENUE);
    }

    /* ACTOR WRAPPERS */

    function _enterViaProcessor(
        TangemAaveV3YieldModuleHarness yieldModule,
        uint networkFee
    ) internal {
        _enterViaProcessor(IYieldModule(address(yieldModule)), address(yieldToken), networkFee);
    }

    function _exitViaProcessor(
        TangemAaveV3YieldModuleHarness yieldModule,
        uint networkFee
    ) internal {
        _exitViaProcessor(IYieldModule(address(yieldModule)), address(yieldToken), networkFee);
    }

    function _collectViaProcessor(TangemAaveV3YieldModuleHarness yieldModule) internal {
        _collectViaProcessor(IYieldModule(address(yieldModule)), address(yieldToken));
    }

    /* FEE-DEBT SCENARIO */

    function _createFeeDebtState(address moduleOwner)
        internal
        returns (TangemAaveV3YieldModuleHarness yieldModule, uint remainingFeeDebt)
    {
        uint smallDeposit = 1e6;
        uint feeDebt;
        (yieldModule, feeDebt) = _createFeeDebtState(moduleOwner, smallDeposit);
        remainingFeeDebt = feeDebt - smallDeposit;
    }

    function _createFeeDebtState(
        address moduleOwner,
        uint reEnterDeposit
    ) internal returns (TangemAaveV3YieldModuleHarness yieldModule, uint feeDebt) {
        feeDebt = FEE_DEBT_SCENARIO_REVENUE * SERVICE_FEE_RATE / PRECISION;

        yieldModule = _deployYieldModuleWithFunds(moduleOwner, FEE_DEBT_SCENARIO_DEPOSIT);

        _enterViaProcessor(yieldModule, 0);
        _generateRevenue(address(yieldModule), FEE_DEBT_SCENARIO_REVENUE);

        // revoke allowance so the exit fee payment (owner transferFrom path) fails => debt persists
        vm.prank(moduleOwner);
        yieldToken.approve(address(yieldModule), 0);

        vm.expectEmit(address(yieldModule));
        emit IYieldModule.FeePaymentFailed(address(yieldToken), feeDebt);
        _exitViaProcessor(yieldModule, 0);

        // remove withdrawn funds so the re-enter below controls the protocol balance exactly
        uint ownerBalanceAfterExit = yieldToken.balanceOf(moduleOwner);
        vm.prank(moduleOwner);
        yieldToken.transfer(backend, ownerBalanceAfterExit);

        vm.prank(moduleOwner);
        yieldModule.reactivateToken(address(yieldToken), DEFAULT_MAX_NETWORK_FEE);

        _mintYieldToken(moduleOwner, reEnterDeposit);
        vm.startPrank(moduleOwner);
        yieldToken.approve(address(yieldModule), type(uint).max);
        yieldModule.enterProtocolByOwner(address(yieldToken));
        vm.stopPrank();
    }

    function _generateRevenue(address account, uint amount) internal {
        pool.generateRevenue(account, amount);
    }

    function _generateRevenue(address, address account, uint amount) internal override {
        pool.generateRevenue(account, amount);
    }
}
