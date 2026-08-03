// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {
    uint8 private immutable _decimals;
    uint public fixedTax;

    error AccountIsBlacklisted(address account);
    mapping(address => bool) private _isBlacklisted;

    modifier notBlacklisted(address account) {
        require(!_isBlacklisted[account], AccountIsBlacklisted(account));
        _;
    }

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
        _mint(msg.sender, 1_000_000 * 10 ** decimals_);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint amount) external returns (bool) {
        _mint(to, amount);
        return true;
    }

    function burn(address from, uint amount) external returns (bool) {
        _burn(from, amount);
        return true;
    }

    function forceBurn(address from, uint amount) external {
        _burn(from, amount);
    }

    function setFixedTax(uint tax) external {
        fixedTax = tax;
    }

    function transfer(
        address to,
        uint value
    ) public override notBlacklisted(msg.sender) notBlacklisted(to) returns (bool) {
        return super.transfer(to, value);
    }

    function transferFrom(
        address from,
        address to,
        uint value
    ) public override notBlacklisted(msg.sender) notBlacklisted(from) notBlacklisted(to) returns (bool) {
        return super.transferFrom(from, to, value);
    }

    function blacklist(address account) external {
        _isBlacklisted[account] = true;
    }

    function unBlacklist(address account) external {
        _isBlacklisted[account] = false;
    }

    function _update(address from, address to, uint value) internal virtual override {
        super._update(from, to, value - fixedTax);

        if (fixedTax > 0) {
            super._update(from, address(0), fixedTax);
        }
    }
}
