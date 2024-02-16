// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Id} from "../../lib/metamorpho/src/interfaces/IMetaMorpho.sol";

/// @title ErrorsLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Library exposing error messages.
library ErrorsLib {
    /// @notice Thrown when the `msg.sender` is not the `owner`.
    error NotOwner();

    /// @notice Thrown when the address passed is the zero address.
    error ZeroAddress();

    /// @notice Thrown when the reallocation fee given is wrong.
    error IncorrectFee();

    /// @notice Thrown when the supply cap has been exceeded on market `id` during a reallocation of funds.
    error PublicAllocatorSupplyCapExceeded(Id id);

    /// @notice Thrown when the value is already set.
    error AlreadySet();

    /// @notice Thrown when there are duplicates with nonzero assets in `reallocateTo` arguments.
    error InconsistentWithdrawTo();

    /// @notice Thrown when attempting to set max inflow/outflow above the MAX_SETTABLE_FLOW_CAP.
    error MaxSettableFlowCapExceeded();

    /// @notice Thrown when the PublicAllocatorFactory is called with a vault not made by the MetaMorphoFactory.
    error NotMetaMorpho();

    /// @notice Thrown when attempting to withdraw more than the available supply of a market.
    error NotEnoughSupply(Id id);

    /// @notice Thrown when attempting to withdraw more than the max outflow of a market.
    error MaxOutflowExceeded(Id id);

    /// @notice Thrown when attempting to supply more than the max inflow of a market.
    error MaxInflowExceeded(Id id);
}
