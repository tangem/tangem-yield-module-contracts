// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TestERC20 } from "./TestERC20.sol";

contract GeneralPoolMock {
    event Deposit(address yieldToken, uint amount);
    event Withdraw(address yieldToken, uint amount, address to);
    event GenerateRevenue(address yieldToken, address account, uint amount);

    mapping(address => TestERC20) public protocolTokens;
    mapping(address => address) public yieldTokensByProtocolToken;

    function initProtocolToken(address yieldToken) public returns (address) {
        TestERC20 protocolToken = protocolTokens[yieldToken];

        if (address(protocolToken) == address(0)) {
            protocolToken = new TestERC20("TestProtocolToken", "ptTST", 18);
            protocolToken.forceBurn(address(this), protocolToken.balanceOf(address(this)));

            protocolTokens[yieldToken] = protocolToken;
            yieldTokensByProtocolToken[address(protocolToken)] = yieldToken;
        }

        return address(protocolToken);
    }

    function deposit(address yieldToken, uint amount) external {
        initProtocolToken(yieldToken);

        IERC20(yieldToken).transferFrom(msg.sender, address(this), amount);
        protocolTokens[yieldToken].mint(msg.sender, amount);

        emit Deposit(yieldToken, amount);
    }

    function withdraw(address yieldToken, uint amount, address to) external returns (uint) {
        TestERC20 protocolToken = protocolTokens[yieldToken];

        if (amount == type(uint).max) {
            amount = protocolToken.balanceOf(msg.sender);
        }

        protocolToken.forceBurn(msg.sender, amount);
        IERC20(yieldToken).transfer(to, amount);

        emit Withdraw(yieldToken, amount, to);

        return amount;
    }

    function generateRevenue(address yieldToken, address account, uint amount) external {
        protocolTokens[yieldToken].mint(account, amount);

        emit GenerateRevenue(yieldToken, account, amount);
    }
}
