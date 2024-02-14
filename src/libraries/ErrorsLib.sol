// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Id} from "../../lib/metamorpho/src/interfaces/IMetaMorpho.sol";

/// @title ErrorsLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Library exposing error messages.
library ErrorsLib {
    /// @notice Thrown when the address passed is the zero address.
    error ZeroAddress();

    /// @notice Thrown when allocation to market `id` exceeds current max inflow
    error InflowCapExceeded(Id id);

    /// @notice Thrown when allocation from market `id` exceeds current max outflow
    error OutflowCapExceeded(Id id);

    /// @notice Thrown when flow configuration for market `id` has min flow > max flow
    error InconsistentFlowConfig(Id id);

    /// @notice Thrown when the reallocation fee given is too low
    error FeeTooLow();

    /// @notice Thrown when the fee recipient fails to receive the fee
    error FeeTransferFail();

    /// @notice Thrown when the supply cap has been exceeded on market `id` during a reallocation of funds.
    error PublicAllocatorSupplyCapExceeded(Id id);

    /// @notice Thrown when the maximum uint128 is exceeded.
    error MaxUint128Exceeded();
}