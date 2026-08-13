// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface INativeSupport {
    function enterProtocolByOwnerWithNative() external payable;

    function withdrawNative(uint amount) external;

    function withdrawAndDeactivateNative() external;
}
