// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IPublicAllocator} from "./IPublicAllocator.sol";
import {IMetaMorphoFactory} from "../../lib/metamorpho/src/interfaces/IMetaMorphoFactory.sol";

/// @title IPublicAllocatorFactory
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Interface of PublicAllocator's factory.
interface IPublicAllocatorFactory {
    /// @notice The address of the MetaMorphoFactory.
    function METAMORPHO_FACTORY() external view returns (IMetaMorphoFactory);

    /// @notice Whether an address is a PublicAllocator created by the factory.
    function isPublicAllocator(address target) external view returns (bool);

    /// @notice Creates a new PublicAllocator.
    /// @param initialOwner The owner of the vault.
    /// @param vault The vault the allocator will be attached to.
    /// @param salt The salt to use for the MetaMorpho vault's CREATE2 address.
    /// @dev Will only create public allocators for vault created by METAMORPHO_FACTORY.
    function createPublicAllocator(address initialOwner, address vault, bytes32 salt)
        external
        returns (IPublicAllocator publicAllocator);
}
