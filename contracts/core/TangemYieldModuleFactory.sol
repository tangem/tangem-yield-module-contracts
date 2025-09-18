// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../interfaces/IYieldProcessor.sol";
import "../interfaces/IYieldModule.sol";

contract TangemYieldModuleFactory is AccessControlEnumerable, Pausable {

    bytes32 public constant IMPLEMENTATION_SETTER_ROLE = keccak256("IMPLEMENTATION_SETTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    bytes32 public constant SALT = keccak256("TangemYieldModuleFactory");

    address public implementation;

    // owner => yield module
    mapping(address => address) public yieldModules;

    event ImplementationSet(address newImplementation);
    event YieldModuleDeployed(address indexed owner, address indexed yieldModule);

    error ModuleAlreadyDeployed();
    error OnlyOwnerInitsToken();

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        _pause();
    }

    function deployYieldModule(
        address owner,
        address yieldToken,
        uint240 maxNetworkFee
    ) external whenNotPaused returns (address yieldModule) {
        require(yieldModules[owner] == address(0), ModuleAlreadyDeployed());
        if (yieldToken != address(0)) {
            require(_msgSender() == owner, OnlyOwnerInitsToken());
        }

        bytes memory initializeData = abi.encodeCall(
            IYieldModule.initialize,
            (owner)
        );
        yieldModule = address(new ERC1967Proxy{salt: SALT}(implementation, initializeData));
        yieldModules[owner] = yieldModule;

        if (yieldToken != address(0)){
            IYieldModule(yieldModule).initYieldToken(yieldToken, maxNetworkFee);
        }

        emit YieldModuleDeployed(owner, yieldModule);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function setImplementation(address newImplementation)
        external
        whenPaused
        onlyRole(IMPLEMENTATION_SETTER_ROLE)
    {
        implementation = newImplementation;

        emit ImplementationSet(newImplementation);
    }

    function calculateYieldModuleAddress(address owner)
        external
        view
        whenNotPaused
        returns (address)
    {
        bytes memory initializeData = abi.encodeCall(
            IYieldModule.initialize,
            (owner)
        );

        return address(uint160(uint(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            SALT,
            keccak256(abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(implementation, initializeData)
            ))
        )))));
    }

    function isValidImplementation(address implementation_) external view returns (bool) {
        return implementation == implementation_;
    }
}