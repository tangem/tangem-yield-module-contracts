// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

import {ISwapExecutionRegistry} from "../interfaces/ISwapExecutionRegistry.sol";

contract SwapExecutionRegistry is AccessControlEnumerable, ISwapExecutionRegistry {
    bytes32 public constant ALLOWLIST_ADMIN_ROLE = keccak256("ALLOWLIST_ADMIN_ROLE");

    mapping(address => bool) public allowedTargets;
    mapping(address => bool) public allowedSpenders;

    constructor(address admin) {
        require(admin != address(0), ZeroAddress());
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ALLOWLIST_ADMIN_ROLE, admin);
    }

    function setTargetAllowed(address target, bool allowed) external onlyRole(ALLOWLIST_ADMIN_ROLE) {
        require(target != address(0), ZeroAddress());
        allowedTargets[target] = allowed;
        emit TargetAllowedSet(target, allowed);
    }

    function setSpenderAllowed(address spender, bool allowed) external onlyRole(ALLOWLIST_ADMIN_ROLE) {
        require(spender != address(0), ZeroAddress());
        allowedSpenders[spender] = allowed;
        emit SpenderAllowedSet(spender, allowed);
    }

    function setTargetsAllowed(address[] calldata targets, bool allowed) external onlyRole(ALLOWLIST_ADMIN_ROLE) {
        uint256 length = targets.length;
        for (uint256 i; i < length; ) {
            address target = targets[i];
            require(target != address(0), ZeroAddress());
            allowedTargets[target] = allowed;
            emit TargetAllowedSet(target, allowed);
            unchecked { 
                ++i; 
            }
        }
    }

    function setSpendersAllowed(address[] calldata spenders, bool allowed) external onlyRole(ALLOWLIST_ADMIN_ROLE) {
        uint256 length = spenders.length;
        for (uint256 i; i < length; ) {
            address spender = spenders[i];
            require(spender != address(0), ZeroAddress());
            allowedSpenders[spender] = allowed;
            emit SpenderAllowedSet(spender, allowed);
            unchecked { 
                ++i; 
            }
        }
    }

    function setTargetsAllowedMany(
        address[] calldata targets, 
        bool[] calldata allowed
    )
        external
        onlyRole(ALLOWLIST_ADMIN_ROLE)
    {
        uint256 length = targets.length;
        require(length == allowed.length, LengthMismatch());
        for (uint256 i; i < length; ) {
            address target = targets[i];
            require(target != address(0), ZeroAddress());
            bool status = allowed[i];
            allowedTargets[target] = status;
            emit TargetAllowedSet(target, status);
            unchecked { 
                ++i; 
            }
        }
    }

    function setSpendersAllowedMany(
        address[] calldata spenders, 
        bool[] calldata allowed
    )
        external
        onlyRole(ALLOWLIST_ADMIN_ROLE)
    {
        uint256 length = spenders.length;
        require(length == allowed.length, LengthMismatch());
        for (uint256 i; i < length; ) {
            address spender = spenders[i];
            require(spender != address(0), ZeroAddress());
            bool status = allowed[i];
            allowedSpenders[spender] = status;
            emit SpenderAllowedSet(spender, status);
            unchecked { 
                ++i; 
            }
        }
    }
}
