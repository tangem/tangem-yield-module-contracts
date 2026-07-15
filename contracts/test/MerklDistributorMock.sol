// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IMerklDistributor } from "../interfaces/IMerklDistributor.sol";

contract MerklDistributorMock {
    function claimWithRecipient(
        address[] calldata users,
        address[] calldata tokens,
        uint[] calldata amounts,
        bytes32[][] calldata proofs,
        address[] calldata recipients,
        bytes[] memory datas
    ) external { }
}
