// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WrappedNativeMock is ERC20 {
    error NativeTransferFailed();

    constructor() ERC20("Wrapped Native", "WNATIVE") { }

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint amount) external {
        _burn(msg.sender, amount);

        (bool success,) = msg.sender.call{ value: amount }("");
        require(success, NativeTransferFailed());
    }
}
