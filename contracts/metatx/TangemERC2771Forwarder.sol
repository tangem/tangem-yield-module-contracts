// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/metatx/ERC2771Forwarder.sol"; // for artifact generation

contract TangemERC2771Forwarder is ERC2771Forwarder {
    constructor() ERC2771Forwarder("Tangem ERC2771 Forwarder") {}
}