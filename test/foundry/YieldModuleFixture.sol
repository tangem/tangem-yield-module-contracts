// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { BaseTest } from "test/foundry/BaseTest.sol";
import { YieldModuleGeneralHarness } from "test/foundry/harnesses/YieldModuleGeneralHarness.sol";
import { YieldModuleHarness } from "test/foundry/harnesses/YieldModuleHarness.sol";
import { TestHelpers } from "test/foundry/utils/TestHelpers.sol";

import { ERC2771Forwarder } from "@openzeppelin/contracts/metatx/ERC2771Forwarder.sol";
import { PRECISION } from "contracts/common/Constants.sol";
import { SwapExecutionRegistry } from "contracts/infra/SwapExecutionRegistry.sol";
import { TangemERC2771Forwarder } from "contracts/infra/TangemERC2771Forwarder.sol";
import { TangemYieldModuleFactory } from "contracts/infra/TangemYieldModuleFactory.sol";
import { TangemYieldProcessor } from "contracts/infra/TangemYieldProcessor.sol";
import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";
import { GeneralPoolMock } from "contracts/test/GeneralPoolMock.sol";
import { MerklDistributorMock } from "contracts/test/MerklDistributorMock.sol";
import { SwapProviderMock } from "contracts/test/SwapProviderMock.sol";
import { TestERC20 } from "contracts/test/TestERC20.sol";

abstract contract YieldModuleFixture is BaseTest, TestHelpers {
    bytes32 internal constant FEE_PAYMENT_FAILED_EVENT_SIG = keccak256("FeePaymentFailed(address,uint256)");

    uint internal constant INITIAL_OWNER_BALANCE = 400_000e6;
    uint internal constant ACCUMULATED_REVENUE = 10_000e6;
    uint internal constant NETWORK_FEE = 1e6;
    uint internal constant NEW_FEE_RATE = 2_000;
    uint internal constant ACCUMULATED_SERVICE_FEE = ACCUMULATED_REVENUE * SERVICE_FEE_RATE / PRECISION;
    uint internal constant PROTOCOL_BALANCE = INITIAL_OWNER_BALANCE + ACCUMULATED_REVENUE;

    uint internal constant FEE_DEBT_SCENARIO_DEPOSIT = 100_000e6;
    uint internal constant FEE_DEBT_SCENARIO_REVENUE = 10_000e6;

    TangemERC2771Forwarder public forwarder;
    TangemYieldProcessor public processor;
    TangemYieldModuleFactory public factory;
    SwapExecutionRegistry public swapExecutionRegistry;
    MerklDistributorMock public merklDistributor;
    SwapProviderMock public swapProvider;
    TestERC20 public yieldToken;
    GeneralPoolMock public generalPool;
    YieldModuleGeneralHarness public ymGeneralImpl;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(backend);

        forwarder = new TangemERC2771Forwarder();

        processor = new TangemYieldProcessor(feeReceiver, SERVICE_FEE_RATE);
        processor.grantRole(processor.PROTOCOL_ENTERER_ROLE(), backend);
        processor.grantRole(processor.PROTOCOL_EXITER_ROLE(), backend);
        processor.grantRole(processor.SERVICE_FEE_COLLECTOR_ROLE(), backend);
        processor.grantRole(processor.PROPERTY_SETTER_ROLE(), backend);
        processor.grantRole(processor.CLAIM_MERKL_REWARDS_ROLE(), backend);
        processor.grantRole(processor.PAUSER_ROLE(), backend);
        processor.grantRole(processor.RISK_SERVICE_ROLE(), backend);

        factory = new TangemYieldModuleFactory();
        swapExecutionRegistry = new SwapExecutionRegistry(backend);
        merklDistributor = new MerklDistributorMock();
        swapProvider = new SwapProviderMock();
        yieldToken = new TestERC20("TestYieldToken", "TYT", 6);

        generalPool = new GeneralPoolMock();
        yieldToken.mint(address(generalPool), POOL_LIQUIDITY);

        ymGeneralImpl = new YieldModuleGeneralHarness(
            address(generalPool),
            address(merklDistributor),
            address(processor),
            address(factory),
            address(forwarder),
            address(swapExecutionRegistry)
        );

        factory.grantRole(factory.IMPLEMENTATION_SETTER_ROLE(), backend);
        factory.grantRole(factory.PAUSER_ROLE(), backend);

        vm.stopPrank();

        _labelAddresses();
    }

    function _labelAddresses() internal virtual {
        vm.label(address(processor), "processor");
        vm.label(address(factory), "factory");
        vm.label(address(swapExecutionRegistry), "swapExecutionRegistry");
        vm.label(address(forwarder), "forwarder");
        vm.label(address(merklDistributor), "merklDistributor");
        vm.label(address(swapProvider), "swapProvider");
        vm.label(address(yieldToken), "yieldToken");
        vm.label(address(generalPool), "generalPool");
        vm.label(address(ymGeneralImpl), "ymGeneralImpl");
    }

    /* DEPLOY (protocol-agnostic — deploys whichever implementation is registered in the factory) */

    function _deployYieldModule(
        address moduleOwner,
        address yieldTokenAddr,
        uint240 maxNetworkFee
    ) internal returns (YieldModuleHarness yieldModule) {
        vm.prank(moduleOwner);
        factory.deployYieldModule(moduleOwner, yieldTokenAddr, maxNetworkFee);

        yieldModule = YieldModuleHarness(payable(factory.calculateYieldModuleAddress(moduleOwner)));
        vm.label(address(yieldModule), "yieldModule");
    }

    /// Deploys a module with the yield token initialized, owner funded and max approval given.
    function _deployYieldModuleWithFunds(
        address moduleOwner,
        uint ownerBalance
    ) internal returns (YieldModuleHarness yieldModule) {
        yieldModule = _deployYieldModule(moduleOwner, address(yieldToken), DEFAULT_MAX_NETWORK_FEE);

        _mintYieldToken(moduleOwner, ownerBalance);

        vm.prank(moduleOwner);
        yieldToken.approve(address(yieldModule), type(uint).max);
    }

    function _deployEnteredYieldModule(
        address moduleOwner,
        uint enterAmount
    ) internal returns (YieldModuleHarness yieldModule) {
        yieldModule = _deployYieldModuleWithFunds(moduleOwner, enterAmount);

        vm.prank(moduleOwner);
        yieldModule.enterProtocolByOwner(address(yieldToken));
    }

    /// Full scenario: deployed, entered and revenue generated (standard ACCUMULATED_REVENUE).
    function _deployEnteredRevenueModule(address moduleOwner) internal returns (YieldModuleHarness yieldModule) {
        yieldModule = _deployYieldModuleWithFunds(moduleOwner, INITIAL_OWNER_BALANCE);
        _enterViaProcessor(yieldModule, 0);
        _generateRevenue(address(yieldToken), address(yieldModule), ACCUMULATED_REVENUE);
    }

    /* HARNESS ACTOR WRAPPERS (bind yieldToken) */

    function _enterViaProcessor(YieldModuleHarness yieldModule, uint networkFee) internal {
        _enterViaProcessor(IYieldModule(address(yieldModule)), address(yieldToken), networkFee);
    }

    function _exitViaProcessor(YieldModuleHarness yieldModule, uint networkFee) internal {
        _exitViaProcessor(IYieldModule(address(yieldModule)), address(yieldToken), networkFee);
    }

    function _collectViaProcessor(YieldModuleHarness yieldModule) internal {
        _collectViaProcessor(IYieldModule(address(yieldModule)), address(yieldToken));
    }

    function _softExitViaProcessor(YieldModuleHarness yieldModule) internal {
        vm.prank(backend);
        processor.softExit(address(yieldModule), address(yieldToken));
    }

    function _softExitViaProcessor(YieldModuleHarness yieldModule, uint amount) internal {
        vm.prank(backend);
        processor.softExit(address(yieldModule), address(yieldToken), amount);
    }

    function _suspendViaProcessor(YieldModuleHarness yieldModule) internal {
        _suspendViaProcessor(yieldModule, address(yieldToken));
    }

    function _suspendViaProcessor(YieldModuleHarness yieldModule, address yieldTokenAddr) internal {
        vm.prank(backend);
        processor.suspendToken(address(yieldModule), yieldTokenAddr);
    }

    function _resumeViaProcessor(YieldModuleHarness yieldModule) internal {
        vm.prank(backend);
        processor.resumeAndEnterProtocol(address(yieldModule), address(yieldToken));
    }

    function _enterViaProcessor(IYieldModule yieldModule, address yieldTokenAddr, uint networkFee) internal {
        vm.prank(backend);
        processor.enterProtocol(address(yieldModule), yieldTokenAddr, networkFee);
    }

    function _exitViaProcessor(IYieldModule yieldModule, address yieldTokenAddr, uint networkFee) internal {
        vm.prank(backend);
        processor.exitProtocol(address(yieldModule), yieldTokenAddr, networkFee);
    }

    function _collectViaProcessor(IYieldModule yieldModule, address yieldTokenAddr) internal {
        vm.prank(backend);
        processor.collectServiceFee(address(yieldModule), yieldTokenAddr);
    }

    function _executeViaForwarder(address target, bytes memory data, uint value) internal {
        uint48 deadline = uint48(block.timestamp + 1 hours);
        uint nonce = forwarder.nonces(owner);

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Tangem ERC2771 Forwarder")),
                keccak256(bytes("1")),
                block.chainid,
                address(forwarder)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,uint48 deadline,bytes data)"
                ),
                owner,
                target,
                value,
                1_000_000,
                nonce,
                deadline,
                keccak256(data)
            )
        );

        bytes32 digest = keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x01), domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);

        ERC2771Forwarder.ForwardRequestData memory request = ERC2771Forwarder.ForwardRequestData({
            from: owner,
            to: target,
            value: value,
            gas: 1_000_000,
            deadline: deadline,
            data: data,
            signature: abi.encodePacked(r, s, v)
        });

        vm.prank(backend);
        forwarder.execute{ value: value }(request);
    }

    /* Helpers */

    function _withdraw(IYieldModule yieldModule, address moduleOwner, address token, uint amount) internal {
        vm.prank(moduleOwner);
        yieldModule.withdraw(token, amount);
    }

    function _withdrawAndDeactivate(IYieldModule yieldModule, address moduleOwner, address token) internal {
        vm.prank(moduleOwner);
        yieldModule.withdrawAndDeactivate(token);
    }

    function _setServiceFeeRate(uint feeRate) internal {
        vm.prank(backend);
        processor.setServiceFeeRate(feeRate);
    }

    function _allowSwapProvider(address provider) internal {
        vm.startPrank(backend);
        swapExecutionRegistry.setTargetAllowed(provider, true);
        swapExecutionRegistry.setSpenderAllowed(provider, true);
        vm.stopPrank();
    }

    function _mintYieldToken(address to, uint amount) internal virtual {
        vm.prank(backend);
        yieldToken.mint(to, amount);
    }

    function _generateRevenue(address yieldTokenAddr, address account, uint amount) internal virtual {
        generalPool.generateRevenue(yieldTokenAddr, account, amount);
    }

    function _registerGeneralImplementation() internal {
        vm.prank(backend);
        factory.setImplementation(address(ymGeneralImpl));
        vm.prank(backend);
        factory.unpause();
    }

    function _assertLatestFeePaymentState(
        YieldModuleHarness yieldModule,
        uint expectedProtocolBalance,
        uint expectedServiceFeeRate
    ) internal view {
        (uint protocolBalance, uint serviceFeeRate) = yieldModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, expectedProtocolBalance, "latestFeePaymentState.protocolBalance");
        assertEq(serviceFeeRate, expectedServiceFeeRate, "latestFeePaymentState.serviceFeeRate");
    }

    /* FEE-DEBT SCENARIO */

    /// Scenario: fee debt persisted after failed fee payment, protocol balance below the debt.
    /// Enter, generate revenue, force fee failure on exit, then reactivate and re-enter with a
    /// small deposit (paid toward the debt). Returns the debt remaining after that payment.
    function _createFeeDebtState(address moduleOwner)
        internal
        returns (YieldModuleHarness yieldModule, uint remainingFeeDebt)
    {
        uint smallDeposit = 1e6;
        uint feeDebt;
        (yieldModule, feeDebt) = _createFeeDebtState(moduleOwner, smallDeposit);
        remainingFeeDebt = feeDebt - smallDeposit;
    }

    /// Same scenario with a configurable re-enter deposit (paid toward the debt).
    /// Returns the full debt as it was before the re-enter payment.
    function _createFeeDebtState(
        address moduleOwner,
        uint reEnterDeposit
    ) internal returns (YieldModuleHarness yieldModule, uint feeDebt) {
        feeDebt = FEE_DEBT_SCENARIO_REVENUE * SERVICE_FEE_RATE / PRECISION;

        yieldModule = _deployYieldModuleWithFunds(moduleOwner, FEE_DEBT_SCENARIO_DEPOSIT);

        _enterViaProcessor(yieldModule, 0);
        _generateRevenue(address(yieldToken), address(yieldModule), FEE_DEBT_SCENARIO_REVENUE);

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
}
