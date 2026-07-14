// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {
    AccessControlEnumerable
} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

import {IMerklDistributorsRegistry} from "../interfaces/IMerklDistributorsRegistry.sol";
import {Requires} from "../common/Requires.sol";

contract MerklDistributorsRegistry is IMerklDistributorsRegistry, AccessControlEnumerable {
    using Requires for address;

    // TODO: do we need separate role for this registry?
    bytes32 public constant ALLOWLIST_ADMIN_ROLE = keccak256("ALLOWLIST_ADMIN_ROLE");

    // distributor => is allowed
    mapping(address => bool) public allowedMerklDistributors;

    constructor(address admin) {
        admin.requireNotZero();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ALLOWLIST_ADMIN_ROLE, admin);
    }

    function setAllowedMerklDistributors(
        address[] calldata distributors,
        bool[] calldata allowances
    ) external onlyRole(ALLOWLIST_ADMIN_ROLE) {
        require(distributors.length == allowances.length, DistributorsLengthsMismatch());

        for (uint256 i; i < distributors.length; ++i) {
            allowedMerklDistributors[distributors[i]] = allowances[i];
        }

        emit MerklDistributorsSet(distributors, allowances);
    }
}
