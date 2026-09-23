// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IWETH } from "contracts/interfaces/external/IWETH.sol";

/// Mimics a Merkl pull token wrapper (`PullTokenWrapperTransferImmutable`): the campaign
/// distributes this wrapper token, and a claim burns it at the recipient and pays out the
/// underlying token held by the wrapper instead. The recipient therefore never ends up with
/// a wrapper balance — only the underlying balance moves.
contract MerklTokenWrapperMock is ERC20 {
    using SafeERC20 for IERC20;

    uint public constant BASE = 1e9;

    IERC20 public immutable underlying;
    address public immutable distributor;

    error NativeTransferFailed();

    /// share of a claim the wrapper withholds, in BASE units;
    uint public claimFeeRate;

    bool public unwrapsToNative;

    constructor(
        address underlying_,
        address distributor_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        underlying = IERC20(underlying_);
        distributor = distributor_;
    }

    receive() external payable { }

    function fundDistributor(uint amount) external {
        _mint(distributor, amount);
    }

    function setClaimFeeRate(uint claimFeeRate_) external {
        claimFeeRate = claimFeeRate_;
    }

    function setUnwrapsToNative(bool unwrapsToNative_) external {
        unwrapsToNative = unwrapsToNative_;
    }

    function _update(address from, address to, uint value) internal override {
        if (from != distributor || to == address(0)) {
            super._update(from, to, value);
            return;
        }

        super._update(from, to, value);
        // the claimer is not allowed to hold the wrapper, so it is burned right back
        super._update(to, address(0), value);

        uint toTransfer = value - value * claimFeeRate / BASE;

        if (toTransfer == 0) {
            return;
        }

        if (unwrapsToNative) {
            IWETH(address(underlying)).withdraw(toTransfer);

            (bool success,) = to.call{ value: toTransfer }("");
            require(success, NativeTransferFailed());

            return;
        }

        underlying.safeTransfer(to, toTransfer);
    }
}
