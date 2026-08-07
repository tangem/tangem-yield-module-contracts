// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { Test } from "forge-std/src/Test.sol";

import { YieldModuleBase } from "contracts/core/YieldModuleBase.sol";
import { SwapExecution } from "contracts/extensions/SwapExecution.sol";

// Pins the frozen slots 0..6 on a module shaped like a real one: the full core chain plus an
// extension. Adding a layer or reordering the bases must not move any of these.
contract StorageLayoutStub is SwapExecution {
    constructor() SwapExecution(address(4)) YieldModuleBase(address(1), address(2), address(3)) { }

    /* solhint-disable no-empty-blocks */
    function initialize(address) external { }

    function _initProtocolToken(address) internal pure override returns (address) {
        return address(0);
    }

    /* solhint-disable no-empty-blocks */
    function _pushToProtocol(address, uint) internal override { }

    function _pullFromProtocolToOwner(address, uint) internal pure override returns (uint) {
        return 0;
    }

    function _pullFromProtocolToModule(address, uint) internal pure override returns (uint) {
        return 0;
    }

    function _tryResolveYieldToken(address) internal pure override returns (address) {
        return address(0);
    }

    function _getProtocolToken(address) internal pure override returns (address) {
        return address(0);
    }
}

contract StorageLayoutTest is Test {
    StorageLayoutStub internal module;
    address internal key = makeAddr("key");

    function setUp() public {
        module = new StorageLayoutStub();
    }

    function _mappingSlot(address mappingKey, uint slotIndex) internal pure returns (bytes32) {
        return keccak256(abi.encode(mappingKey, slotIndex));
    }

    function test_slot0_owner() public {
        address value = makeAddr("ownerValue");
        vm.store(address(module), bytes32(uint(0)), bytes32(uint(uint160(value))));
        assertEq(module.owner(), value);
    }

    function test_slot1_yieldTokensData() public {
        uint240 maxNetworkFeeValue = 123_456_789;
        bytes32 packed = bytes32((uint(maxNetworkFeeValue) << 16) | (1 << 8) | 1);
        vm.store(address(module), _mappingSlot(key, 1), packed);

        (bool initialized, bool active, uint240 maxNetworkFee) = module.yieldTokensData(key);
        assertTrue(initialized);
        assertTrue(active);
        assertEq(maxNetworkFee, maxNetworkFeeValue);
    }

    function test_slot2_protocolTokens() public {
        address value = makeAddr("protocolToken");
        vm.store(address(module), _mappingSlot(key, 2), bytes32(uint(uint160(value))));
        assertEq(address(module.protocolTokens(key)), value);
    }

    function test_slot3_latestFeePaymentStates() public {
        uint protocolBalanceValue = 111e18;
        uint serviceFeeRateValue = 222;
        bytes32 baseSlot = _mappingSlot(key, 3);
        vm.store(address(module), baseSlot, bytes32(protocolBalanceValue));
        vm.store(address(module), bytes32(uint(baseSlot) + 1), bytes32(serviceFeeRateValue));

        (uint protocolBalance, uint serviceFeeRate) = module.latestFeePaymentStates(key);
        assertEq(protocolBalance, protocolBalanceValue);
        assertEq(serviceFeeRate, serviceFeeRateValue);
    }

    function test_slot4_feeDebts() public {
        uint value = 333e18;
        vm.store(address(module), _mappingSlot(key, 4), bytes32(value));
        assertEq(module.feeDebts(key), value);
    }

    function test_slot5_isProtocolToken() public {
        vm.store(address(module), _mappingSlot(key, 5), bytes32(uint(1)));
        assertTrue(module.isProtocolToken(key));
    }

    function test_slot6_yieldTokenByProtocolToken() public {
        address value = makeAddr("yieldToken");
        vm.store(address(module), _mappingSlot(key, 6), bytes32(uint(uint160(value))));
        assertEq(module.yieldTokenByProtocolToken(key), value);
    }
}
