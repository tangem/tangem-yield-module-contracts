// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface IMerklDistributor {
    function claimWithRecipient(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs,
        address[] calldata recipients,
        bytes[] memory datas
    ) external;

    // TODO: is it needed to FE or BE?
    function getMerkleRoot() external view returns (bytes32);
}
