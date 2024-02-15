// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {FlowConfig, SupplyConfig} from "../interfaces/IPublicAllocator.sol";

/// @title EventsLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Library exposing events.
library EventsLib {
    /// @notice Emitted when the public reallocation is triggered.
    event PublicReallocate(address sender);

    /// @notice Emitted when the owner changes the `fee`.
    event SetFee(uint256 fee);

    /// @notice Emitted when the owner transfers the fee.
    event TransferFee(uint256 amount);

    /// @notice Emitted when the owner updates some flow caps.
    event SetFlowCaps(FlowConfig[] flowCaps);

    /// @notice Emitted when the owner updates some supply caps.
    event SetSupplyCaps(SupplyConfig[] supplyCaps);
}
