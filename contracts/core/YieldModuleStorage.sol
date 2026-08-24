// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract YieldModuleStorage {
    struct YieldTokenData {
        bool initialized;
        bool active;
        uint240 maxNetworkFee;
    }

    struct LatestFeePaymentState {
        uint protocolBalance;
        uint serviceFeeRate;
    }

    address public owner;

    mapping(address yieldToken => YieldTokenData) public yieldTokensData;

    mapping(address yieldToken => IERC20 protocolToken) public protocolTokens;

    mapping(address yieldToken => LatestFeePaymentState) public latestFeePaymentStates;

    mapping(address yieldToken => uint feeDebt) public feeDebts;

    mapping(address protocolToken => bool) public isProtocolToken;

    mapping(address protocolToken => address yieldToken) public yieldTokenByProtocolToken;

    mapping(address yieldToken => bool) public entrySuspended;
}
