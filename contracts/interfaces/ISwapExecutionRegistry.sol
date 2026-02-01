// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface ISwapExecutionRegistry {
    error ZeroAddress();
    error LengthMismatch();
    
    event TargetAllowedSet(address indexed target, bool allowed);
    event SpenderAllowedSet(address indexed spender, bool allowed);

    function setTargetAllowed(address target, bool allowed) external;
    function setTargetsAllowed(address[] calldata targets, bool allowed) external;
    function setSpendersAllowed(address[] calldata spenders, bool allowed) external;
    function setTargetsAllowedMany(address[] calldata targets, bool[] calldata allowed) external;
    function setSpendersAllowedMany(address[] calldata spenders, bool[] calldata allowed) external;
    function allowedTargets(address target) external view returns (bool allowed);
    function allowedSpenders(address spender) external view returns (bool allowed);
    function ALLOWLIST_ADMIN_ROLE() external pure returns (bytes32);
}