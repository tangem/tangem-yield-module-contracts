// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { Requires } from "../common/Requires.sol";
import { YieldModuleLiquidUpgradeable } from "../core/YieldModuleLiquidUpgradeable.sol";
import { INativeSupport } from "../interfaces/INativeSupport.sol";
import { IWETH } from "../interfaces/external/IWETH.sol";

abstract contract NativeSupport is INativeSupport, YieldModuleLiquidUpgradeable {
    using Requires for uint;
    using Requires for address;

    address public immutable wrappedNative;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address wrappedNative_) {
        wrappedNative_.requireNotZero();

        wrappedNative = wrappedNative_;
    }

    function enterProtocolByOwnerWithNative() external payable onlyOwner nonReentrant {
        _requireEntryAllowed(wrappedNative);

        uint amount = address(this).balance;
        amount.requireNotZero();

        IWETH(wrappedNative).deposit{ value: amount }();

        _processDeposit(wrappedNative, 0);
    }

    function withdrawNative(uint amount) external onlyOwner nonReentrant {
        uint withdrawnAmount = _withdraw(wrappedNative, amount, true);

        _unwrapToOwner(withdrawnAmount);
    }

    function withdrawAndDeactivateNative() external onlyOwner nonReentrant {
        uint withdrawnAmount = _withdrawAndDeactivate(wrappedNative, true);

        if (withdrawnAmount > 0) {
            _unwrapToOwner(withdrawnAmount);
        }
    }

    function _unwrapToOwner(uint amount) private {
        IWETH(wrappedNative).withdraw(amount);

        (bool success,) = owner.call{ value: amount }("");
        require(success, NativeTransferFailed());
    }
}
