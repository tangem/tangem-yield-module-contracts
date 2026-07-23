// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { DataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

import { MerklIncentivesBase } from "./MerklIncentivesBase.sol";
import { IAToken } from "contracts/interfaces/IAToken.sol";
import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";

/// Covers the lazy recovery of `yieldTokenByProtocolToken` (_resolveAndSetYieldTokenByProtocolToken)
contract YieldTokenByProtocolTokenTest is MerklIncentivesBase {
    function setUp() public override {
        super.setUp();

        ym = _deployEnteredRevenueModule(owner);

        // simulate an old module that never filled the mapping
        ym.exposed_setYieldTokenByProtocolToken(address(protocolToken), address(0));
    }

    function test_claim_RestoresMapping_WhenNotSet() public {
        _mockUnderlyingAsset(address(yieldToken));
        _fundMerklDistributor(address(protocolToken), YIELD_AMOUNT);

        vm.expectEmit(address(ym));
        emit IYieldModule.YieldTokensByProtocolTokensSet(address(yieldToken));

        _claimSingleAsOwner(address(protocolToken), YIELD_AMOUNT);

        assertEq(ym.yieldTokenByProtocolToken(address(protocolToken)), address(yieldToken));
        assertEq(ym.protocolBalance(address(yieldToken)), PROTOCOL_BALANCE + YIELD_AMOUNT);
    }

    function test_claim_Reverts_WhenResolvedYieldTokenNotInitialized() public {
        address unknownUnderlying = makeAddr("unknownUnderlying");

        _mockUnderlyingAsset(unknownUnderlying);
        _fundMerklDistributor(address(protocolToken), YIELD_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(IYieldModule.YieldTokenNotInitialized.selector, unknownUnderlying));

        _claimSingleAsOwner(address(protocolToken), YIELD_AMOUNT);
    }

    function test_claim_Reverts_WhenProtocolReturnsDifferentUnderlyingToken() public {
        _mockUnderlyingAsset(address(yieldToken));
        _fundMerklDistributor(address(protocolToken), YIELD_AMOUNT);

        DataTypes.ReserveData memory reserveData;
        reserveData.aTokenAddress = makeAddr("otherAToken");
        vm.mockCall(
            address(pool),
            abi.encodeWithSelector(pool.getReserveData.selector, address(yieldToken)),
            abi.encode(reserveData)
        );

        vm.expectRevert(abi.encodeWithSelector(IYieldModule.YieldTokenNotInitialized.selector, address(0)));

        _claimSingleAsOwner(address(protocolToken), YIELD_AMOUNT);
    }

    function test_resolveYieldToken_Reverts_WhenTokenIsNotProtocolToken() public {
        address fakeAToken = makeAddr("fakeAToken");

        // underlying resolves to an initialized yield token, but the module never
        // registered this token as a protocol token
        vm.mockCall(
            fakeAToken,
            abi.encodeWithSelector(IAToken.UNDERLYING_ASSET_ADDRESS.selector),
            abi.encode(address(yieldToken))
        );

        vm.expectRevert(abi.encodeWithSelector(IYieldModule.ProtocolTokenNotSet.selector, fakeAToken));

        ym.exposed_resolveYieldToken(fakeAToken);
    }

    function _mockUnderlyingAsset(address underlying) internal {
        vm.mockCall(
            address(protocolToken),
            abi.encodeWithSelector(IAToken.UNDERLYING_ASSET_ADDRESS.selector),
            abi.encode(underlying)
        );
    }
}
