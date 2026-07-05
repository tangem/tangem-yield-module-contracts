// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import "./TestERC20.sol";

contract AaveV3PoolMock {

    event Supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode);
    event Withdraw(address asset, uint256 amount, address to);
    event GenerateRevenue(address account, uint amount);

    TestERC20 public aToken;
    bool public failSupply; // test toggle to simulate a reverting pool.supply
    bool public failWithdraw; // test toggle to simulate a reverting pool.withdraw

    constructor() {
        aToken = new TestERC20();
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

    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external {
        require(!failSupply, "MOCK_SUPPLY_FAIL");
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        aToken.mint(msg.sender, amount);

        emit Supply(asset, amount, onBehalfOf, referralCode);
    }

    function withdraw(address asset, uint256 amount, address to) external returns (uint) {
        require(!failWithdraw, "MOCK_WITHDRAW_FAIL");
        if (amount == type(uint256).max) {
            amount = aToken.balanceOf(msg.sender);
        }

        aToken.forceBurn(msg.sender, amount);
        IERC20(asset).transfer(to, amount); // make sure there is enough balance

        emit Withdraw(asset, amount, to);

        return amount;
    }

    function generateRevenue(address account, uint amount) external {
        aToken.mint(account, amount);

        emit GenerateRevenue(account, amount);
    }
}