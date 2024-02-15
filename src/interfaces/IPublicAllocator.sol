// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.21;

import {
    IMetaMorpho,
    IMorpho,
    MarketAllocation,
    Id,
    IOwnable,
    MarketParams
} from "../../lib/metamorpho/src/interfaces/IMetaMorpho.sol";

struct FlowCap {
    uint128 maxIn;
    uint128 maxOut;
}

struct FlowConfig {
    Id id;
    FlowCap cap;
}

struct SupplyConfig {
    Id id;
    uint256 cap;
}

struct Withdrawal {
    MarketParams marketParams;
    uint128 amount;
}

/// @dev This interface is used for factorizing IPublicAllocatorStaticTyping and IPublicAllocator.
/// @dev Consider using the IPublicAllocator interface instead of this one.
interface IPublicAllocatorBase {
    function fee() external view returns (uint256);
    function VAULT() external view returns (IMetaMorpho);
    function MORPHO() external view returns (IMorpho);
    function supplyCap(Id) external view returns (uint256);

    function withdrawTo(Withdrawal[] calldata withdrawals, MarketParams calldata depositMarketParams)
        external
        payable;
    function setFee(uint256 _fee) external;
    function transferFee(address payable feeRecipient) external;
    function setFlowCaps(FlowConfig[] calldata _flowCaps) external;
    function setSupplyCaps(SupplyConfig[] calldata _supplyCaps) external;
}

/// @dev This interface is inherited by PublicAllocator so that function signatures are checked by the compiler.
/// @dev Consider using the IPublicAllocator interface instead of this one.
interface IPublicAllocatorStaticTyping is IPublicAllocatorBase {
    function flowCap(Id) external view returns (uint128, uint128);
}

/// @title IPublicAllocator
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @dev Use this interface for PublicAllocator to have access to all the functions with the appropriate function
/// signatures.
interface IPublicAllocator is IOwnable, IPublicAllocatorBase {
    function flowCap(Id) external view returns (FlowCap memory);
}
