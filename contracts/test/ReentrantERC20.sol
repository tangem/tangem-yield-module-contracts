// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { TestERC20 } from "./TestERC20.sol";

contract ReentrantERC20 is TestERC20 {
    address public hookTarget;
    bytes public hookData;
    bool private _inHook;

    error HookCallFailed();

    constructor(string memory name, string memory symbol, uint8 decimals_) TestERC20(name, symbol, decimals_) { }

    function setHook(address target, bytes calldata data) external {
        hookTarget = target;
        hookData = data;
    }

    function execute(address target, bytes calldata data) external returns (bytes memory ret) {
        bool success;
        (success, ret) = target.call(data);
        if (!success) _bubbleRevert(ret);
    }

    function _update(address from, address to, uint value) internal override {
        super._update(from, to, value);

        if (hookTarget != address(0) && !_inHook) {
            _inHook = true;
            (bool success, bytes memory ret) = hookTarget.call(hookData);
            _inHook = false;
            if (!success) _bubbleRevert(ret);
        }
    }

    function _bubbleRevert(bytes memory ret) private pure {
        if (ret.length > 0) {
            assembly {
                revert(add(ret, 0x20), mload(ret))
            }
        }
        revert HookCallFailed();
    }
}
