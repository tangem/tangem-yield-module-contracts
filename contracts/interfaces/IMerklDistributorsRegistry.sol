// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface IMerklDistributorsRegistry {
    error DistributorNotAllowed(address distributor);
    error DistributorsLengthsMismatch();

    event MerklDistributorsSet(address[] distributors, bool[] allowances);

    function allowedMerklDistributors(address distributor) external view returns (bool);

    function setAllowedMerklDistributors(
        address[] calldata distributors,
        bool[] calldata allowances
    ) external;
}
