// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TestERC20 is ERC20, Ownable {
    uint fixedTax = 0;

    constructor() ERC20("TestERC20", "TEST") Ownable(msg.sender) {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }

    function mint(address to, uint amount) external onlyOwner {
        _mint(to, amount);
    }

    function forceBurn(address from, uint amount) external onlyOwner {
        _burn(from, amount);
    }

    function setFixedTax(uint tax) external onlyOwner {
        fixedTax = tax;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value - fixedTax);

        if (fixedTax > 0) {
            super._update(from, address(0), fixedTax);
        }
    }
}