// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TangemAaveV3YieldModuleHarness } from "../harnesses/TangemAaveV3YieldModuleHarness.sol";
import { TangemAaveV3YieldModuleBase } from "./base/TangemAaveV3YieldModuleBase.sol";

import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";

contract WithdrawNonYieldTokenTest is TangemAaveV3YieldModuleBase {
    uint internal constant MODULE_BALANCE = 4_000_000e6;

    TangemAaveV3YieldModuleHarness internal yieldModule;
    address internal nonYieldToken;

    function setUp() public override {
        super.setUp();

        yieldModule = _deployYieldModule(owner, address(0), 0);
        _mintYieldToken(address(yieldModule), MODULE_BALANCE);

        nonYieldToken = address(yieldToken);
    }

    function test_withdrawNonYieldToken_TransfersTotalModuleBalanceToOwner() public {
        vm.expectEmit(nonYieldToken);
        emit IERC20.Transfer(address(yieldModule), owner, MODULE_BALANCE);

        vm.prank(owner);
        yieldModule.withdrawNonYieldToken(nonYieldToken);
    }

    function test_withdrawNonYieldToken_RevertsWithdrawingYieldToken() public {
        vm.prank(owner);
        yieldModule.initYieldToken(address(yieldToken), DEFAULT_MAX_NETWORK_FEE);

        vm.expectRevert(IYieldModule.WithdrawingYieldToken.selector);
        vm.prank(owner);
        yieldModule.withdrawNonYieldToken(address(yieldToken));
    }

    function test_withdrawNonYieldToken_RevertsWithdrawingProtocolToken() public {
        vm.prank(owner);
        yieldModule.initYieldToken(address(yieldToken), DEFAULT_MAX_NETWORK_FEE);

        vm.expectRevert(IYieldModule.WithdrawingProtocolToken.selector);
        vm.prank(owner);
        yieldModule.withdrawNonYieldToken(address(protocolToken));
    }

    function test_withdrawNonYieldToken_RevertsOnlyOwner() public {
        vm.expectRevert(IYieldModule.OnlyOwner.selector);
        vm.prank(otherAccount);
        yieldModule.withdrawNonYieldToken(nonYieldToken);
    }

    function test_withdrawNonYieldToken_EmitsWithdrawNonYieldProcessed() public {
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.WithdrawNonYieldProcessed(nonYieldToken, MODULE_BALANCE);

        vm.prank(owner);
        yieldModule.withdrawNonYieldToken(nonYieldToken);
    }
}
