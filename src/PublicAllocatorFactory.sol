// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;

import {IPublicAllocator} from "./interfaces/IPublicAllocator.sol";
import {IPublicAllocatorFactory} from "./interfaces/IPublicAllocatorFactory.sol";
import {IMetaMorphoFactory} from "../lib/metamorpho/src/interfaces/IMetaMorphoFactory.sol";

import {EventsLib} from "./libraries/EventsLib.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";

import {PublicAllocator} from "./PublicAllocator.sol";

/// @title PublicAllocatorFactory
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice This contract allows to create public allocators for MetaMorpho vaults, and to index them easily.
contract PublicAllocatorFactory is IPublicAllocatorFactory {
    /* IMMUTABLES */

    /// @inheritdoc IPublicAllocatorFactory
    IMetaMorphoFactory public immutable METAMORPHO_FACTORY;

    /* STORAGE */

    /// @inheritdoc IPublicAllocatorFactory
    mapping(address => bool) public isPublicAllocator;

    /* CONSTRUCTOR */

    /// @dev Initializes the contract.
    /// @param metaMorphoFactory The address of the MetaMorpho Factory.
    constructor(address metaMorphoFactory) {
        if (metaMorphoFactory == address(0)) revert ErrorsLib.ZeroAddress();

        METAMORPHO_FACTORY = IMetaMorphoFactory(metaMorphoFactory);
    }

    /* EXTERNAL */

    /// @inheritdoc IPublicAllocatorFactory
    function createPublicAllocator(address initialOwner, address vault, bytes32 salt)
        external
        returns (IPublicAllocator publicAllocator)
    {
        if (!METAMORPHO_FACTORY.isMetaMorpho(vault)) {
            revert ErrorsLib.NotMetaMorpho();
        }

        publicAllocator = IPublicAllocator(address(new PublicAllocator{salt: salt}(initialOwner, vault)));

        isPublicAllocator[address(publicAllocator)] = true;

        emit EventsLib.CreatePublicAllocator(address(publicAllocator), msg.sender, initialOwner, vault, salt);
    }
}
