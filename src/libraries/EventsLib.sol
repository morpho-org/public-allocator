// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {FlowConfig, SupplyConfig, Id} from "../interfaces/IPublicAllocator.sol";

/// @title EventsLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Library exposing events.
library EventsLib {
    /// @notice Emitted during a public reallocation for each withdrawn-from market
    event PublicWithdrawal(Id id, uint256 withdrawnAssets);
    /// @notice Emitted at the end of a public reallocation
    event PublicReallocateTo(address sender, uint256 fee, Id depositMarketId, uint256 depositedAssets);

    /// @notice Emitted when the owner changes the `fee`
    event SetFee(uint256 fee);
    /// @notice Emitted when the owner transfers the fee.
    event TransferFee(uint256 amount);
    /// @notice Emitted when the owner updates some flow caps.
    event SetFlowCaps(FlowConfig[] flowCaps);
    /// @notice Emitted when the owner updates some supply caps.
    event SetSupplyCaps(SupplyConfig[] supplyCaps);
}
