// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ErrorsLib} from "../libraries/ErrorsLib.sol";

/// @title UtilsLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Library exposing helpers.
/// @dev Inspired by https://github.com/morpho-org/morpho-utils.
library UtilsLib {
    /// @dev Returns `x` safely cast to uint128.
    function toUint128(uint256 x) internal pure returns (uint128) {
        if (x > type(uint128).max) revert ErrorsLib.MaxUint128Exceeded();
        return uint128(x);
    }

    // Returns min(x+y,type(uint128).max)
    function saturatingAdd(uint128 x, uint128 y) internal pure returns (uint128 z) {
        assembly ("memory-safe") {
            let sum := add(x, y)
            let ceil := 0x00000000000000000000000000000000ffffffffffffffffffffffffffffffff
            z := xor(sum, mul(xor(sum, ceil), lt(ceil, sum)))
        }
    }
}
