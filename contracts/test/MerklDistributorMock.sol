// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IMerklDistributor } from "contracts/interfaces/external/IMerklDistributor.sol";

/// Mimics Merkl Distributor claim semantics: `amounts` are lifetime cumulative amounts
/// per (user, token), each claim transfers only the delta over what was already claimed.
/// Proofs are not verified. Fund rewards by minting/dealing tokens to this contract.
contract MerklDistributorMock is IMerklDistributor {
    using SafeERC20 for IERC20;

    error ArraysLengthsMismatch();
    error InvalidProof();

    mapping(address user => mapping(address token => uint)) public claimed;

    /* solhint-disable gas-calldata-parameters */
    function claimWithRecipient(
        address[] calldata users,
        address[] calldata tokens,
        uint[] calldata amounts,
        bytes32[][] calldata proofs,
        address[] calldata recipients,
        bytes[] memory datas
    ) external {
        require(
            users.length == tokens.length && tokens.length == amounts.length && amounts.length == proofs.length
                && proofs.length == recipients.length && recipients.length == datas.length,
            ArraysLengthsMismatch()
        );

        for (uint i; i < users.length; ++i) {
            // Underflows (reverts) if the cumulative amount is below what was already
            // claimed — matches the real distributor rejecting a stale claim.
            uint toSend = amounts[i] - claimed[users[i]][tokens[i]];
            claimed[users[i]][tokens[i]] = amounts[i];

            // toSend == 0 is intentionally not a revert here: it lets tests exercise
            // the module's own MerklClaimedNoReward check.
            if (toSend > 0) {
                IERC20(tokens[i]).safeTransfer(recipients[i], toSend);
            }
        }
    }
}
