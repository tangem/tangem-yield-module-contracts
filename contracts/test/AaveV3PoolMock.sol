// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { DataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TestERC20 } from "./TestERC20.sol";

contract AaveV3PoolMock {
    event Supply(address asset, uint amount, address onBehalfOf, uint16 referralCode);
    event Withdraw(address asset, uint amount, address to);
    event GenerateRevenue(address account, uint amount);

    error SupplyFailed();
    error WithdrawFailed();

    TestERC20 public aToken;
    uint public withdrawBurnShortfall;
    bool public failSupply; // test toggle to simulate a reverting pool.supply
    bool public failWithdraw; // test toggle to simulate a reverting pool.withdraw

    constructor() {
        aToken = new TestERC20("AaveV3MockAToken", "aTST", 6);
    }

    // simulates aToken index rounding: burns slightly less than withdrawn, leaving dust on the account
    function setWithdrawBurnShortfall(uint shortfall) external {
        withdrawBurnShortfall = shortfall;
    }

    function setFailSupply(bool value) external {
        failSupply = value;
    }

    function setFailWithdraw(bool value) external {
        failWithdraw = value;
    }

    function getReserveData(address) external view returns (DataTypes.ReserveData memory) {
        return DataTypes.ReserveData(
            DataTypes.ReserveConfigurationMap(0),
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            address(aToken),
            address(0),
            address(0),
            address(0),
            0,
            0,
            0
        );
    }

    function supply(address asset, uint amount, address onBehalfOf, uint16 referralCode) external {
        require(!failSupply, SupplyFailed());

        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        aToken.mint(msg.sender, amount);

        emit Supply(asset, amount, onBehalfOf, referralCode);
    }

    function withdraw(address asset, uint amount, address to) external returns (uint) {
        require(!failWithdraw, WithdrawFailed());

        if (amount == type(uint).max) {
            amount = aToken.balanceOf(msg.sender);
        }

        uint burnAmount = amount > withdrawBurnShortfall ? amount - withdrawBurnShortfall : 0;

        aToken.forceBurn(msg.sender, burnAmount);
        IERC20(asset).transfer(to, amount); // make sure there is enough balance

        emit Withdraw(asset, amount, to);

        return amount;
    }

    function generateRevenue(address account, uint amount) external {
        aToken.mint(account, amount);

        emit GenerateRevenue(account, amount);
    }
}
