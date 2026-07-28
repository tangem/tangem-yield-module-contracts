// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { ERC2771ContextUpgradeable } from "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ReentrancyGuardTransientUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

import { Requires } from "../common/Requires.sol";
import { IYieldFactory } from "../interfaces/IYieldFactory.sol";
import { IYieldModule } from "../interfaces/IYieldModule.sol";
import { IYieldProcessor } from "../interfaces/IYieldProcessor.sol";
import { YieldModuleStorage } from "./YieldModuleStorage.sol";

abstract contract YieldModuleBase is
    YieldModuleStorage,
    Initializable,
    ERC2771ContextUpgradeable,
    IYieldModule,
    UUPSUpgradeable,
    ReentrancyGuardTransientUpgradeable
{
    using Requires for address;

    IYieldProcessor public immutable processor;
    IYieldFactory public immutable factory;

    modifier onlyOwner() {
        require(_msgSender() == owner, OnlyOwner());
        _;
    }

    modifier onlyOwnerOrFactory() {
        address msgSender = _msgSender();
        require(msgSender == owner || msgSender == address(factory), OnlyOwnerOrFactory());
        _;
    }

    modifier onlyProcessor() {
        require(_msgSender() == address(processor), OnlyProcessor());
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address processor_,
        address factory_,
        address trustedForwarder_
    ) ERC2771ContextUpgradeable(trustedForwarder_) {
        processor = IYieldProcessor(processor_);
        factory = IYieldFactory(factory_);
    }

    receive() external payable { }

    function __YieldModule_init(address owner_) internal onlyInitializing {
        __ReentrancyGuardTransient_init();
        __YieldModule_init_unchained(owner_);
    }

    function __YieldModule_init_unchained(address owner_) internal onlyInitializing {
        owner = owner_;
    }

    function _protocolBalance(address yieldToken) internal view returns (uint) {
        return protocolTokens[yieldToken].balanceOf(address(this));
    }

    function _resolveYieldToken(address protocolToken) internal returns (address) {
        address yieldToken = yieldTokenByProtocolToken[protocolToken];

        if (yieldToken != address(0)) {
            return yieldToken;
        }

        return _resolveAndSetYieldTokenByProtocolToken(protocolToken);
    }

    function _resolveAndSetYieldTokenByProtocolToken(address protocolToken) internal returns (address yieldToken) {
        require(isProtocolToken[protocolToken], ProtocolTokenNotSet(protocolToken));

        yieldToken = _tryResolveYieldToken(protocolToken);
        require(yieldTokensData[yieldToken].initialized, YieldTokenNotInitialized(yieldToken));

        yieldTokenByProtocolToken[protocolToken] = yieldToken;
        emit YieldTokensByProtocolTokensSet(yieldToken);
    }

    /* PORT FOR ADAPTERS */

    function _initProtocolToken(address yieldToken) internal virtual returns (address);

    function _pushToProtocol(address yieldToken, uint amount) internal virtual;

    function _pullFromProtocolToOwner(address yieldToken, uint amount) internal virtual returns (uint);

    function _pullFromProtocolToModule(address yieldToken, uint amount) internal virtual returns (uint);

    function _tryResolveYieldToken(address protocolToken) internal view virtual returns (address);

    function _getProtocolToken(address yieldToken) internal view virtual returns (address);

    /* UPGRADE */

    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        require(factory.isValidImplementation(newImplementation), UnauthorizedImplementation());
    }
}
