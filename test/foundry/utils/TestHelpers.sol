// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Vm } from "forge-std/src/Test.sol";

import { BaseTest } from "../BaseTest.sol";
import { TestERC20 } from "contracts/test/TestERC20.sol";

/// Shared test helpers reused across feature suites via multiple inheritance.
abstract contract TestHelpers is BaseTest {
    function _accessControlError(address account, bytes32 role) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, account, role);
    }

    function _assertEventNotEmitted(Vm.Log[] memory entries, bytes32 eventSig) internal pure {
        for (uint i; i < entries.length; i++) {
            require(entries[i].topics[0] != eventSig, "expected event not to be emitted");
        }
    }

    function _deployTestToken() internal returns (TestERC20 token) {
        vm.prank(backend);
        token = new TestERC20("TestToken", "TST", 18);
    }

    function _mintToken(TestERC20 token, address to, uint amount) internal {
        vm.prank(backend);
        token.mint(to, amount);
    }
}
