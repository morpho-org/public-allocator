// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {FlowCapsConfig, Id} from "../interfaces/IPublicAllocator.sol";

/// @title EventsLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Library exposing events.
library EventsLib {
    /// @notice Emitted during a public reallocation for each withdrawn-from market.
    event PublicWithdrawal(address indexed vault, Id id, uint256 withdrawnAssets);

    /// @notice Emitted at the end of a public reallocation.
    event PublicReallocateTo(address indexed vault, address sender, Id supplyMarketId, uint256 suppliedAssets);

    /// @notice Emitted when the owner is set for a vault.
    event SetOwner(address indexed vault, address owner);

    /// @notice Emitted when the owner changes the `fee` for a vault.
    event SetFee(address indexed vault, uint256 fee);

    /// @notice Emitted when the owner transfers the fee for a vault.
    event TransferFee(address indexed vault, uint256 amount, address indexed feeRecipient);

    /// @notice Emitted when the owner updates some flow caps for a vault.
    event SetFlowCaps(address indexed vault, FlowCapsConfig[] config);
}
