// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {FlowCapsConfig, SupplyCapConfig, Id} from "../interfaces/IPublicAllocator.sol";

/// @title EventsLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Library exposing events.
library EventsLib {
    /// @notice Emitted during a public reallocation for each withdrawn-from market.
    event PublicWithdrawal(Id id, uint256 withdrawnAssets);

    /// @notice Emitted at the end of a public reallocation.
    event PublicReallocateTo(address sender, Id supplyMarketId, uint256 suppliedAssets);

    /// @notice Emitted when the owner is set.
    event SetOwner(address owner);
    
    /// @notice Emitted when the owner changes the `fee`
    event SetFee(uint256 fee);

    /// @notice Emitted when the owner transfers the fee.
    event TransferFee(uint256 amount, address indexed feeRecipient);

    /// @notice Emitted when the owner updates some flow caps.
    event SetFlowCaps(FlowCapsConfig[] config);

    /// @notice Emitted when the owner updates some supply caps.
    event SetSupplyCaps(SupplyCapConfig[] config);

    /// @notice Emitted when a new PublicAllocator is created.
    /// @param publicAllocator The address of the created PublicAllocator.
    /// @param caller The caller of the function.
    /// @param initialOwner The initial owner of the PublicAllocator.
    /// @param vault The MetaMorpho vault attached to the PublicAllocator.
    /// @param salt The salt used for the PublicAllocator's CREATE2 address.
    event CreatePublicAllocator(
        address indexed publicAllocator, address indexed caller, address initialOwner, address vault, bytes32 salt
    );
}
