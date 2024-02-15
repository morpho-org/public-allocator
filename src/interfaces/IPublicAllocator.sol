// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.21;

import {IMetaMorpho, IMorpho, MarketAllocation, Id} from "../../lib/metamorpho/src/interfaces/IMetaMorpho.sol";

struct FlowCap {
    /// @notice The maximum allowed inflow in a market
    uint128 maxIn;
    /// @notice The maximum allowed outflow in a market
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

/// @dev This interface is used for factorizing IPublicAllocatorStaticTyping and IPublicAllocator.
/// @dev Consider using the IPublicAllocator interface instead of this one.
interface IPublicAllocatorBase {
    /// @notice The address of the owner of the public allocator.
    function OWNER() external view returns (address);

    /// @notice The address of the vault where the public allocator calls reallocate.
    function VAULT() external view returns (IMetaMorpho);

    /// @notice The address of the Morpho contract.
    function MORPHO() external view returns (IMorpho);
    
    /// @notice The current fee.
    function fee() external view returns (uint256);

    /// @notice Given a market, the cap a supply through public allocation cannot exceed.
    /// @notice A withdraw through public allocation can start and end above the cap.
    function supplyCap(Id) external view returns (uint256);

    /// @notice Calls the vault's `reallocate` function.
    /// @notice See MetaMorpho's `reallocate` function documentation.
    /// @dev Checks that the public allocator constraints are respected.
    function reallocate(MarketAllocation[] calldata allocations) external payable;

    /// @notice Set the current fee.
    function setFee(uint256 _fee) external;

    /// @notice Transfer the current balance to `feeRecipient`.
    function transferFee(address payable feeRecipient) external;

    /// @notice Sets the maximum inflow and outflow through public allocation for some markets.
    /// @dev Doesn't revert if it doesn't change the storage at all.
    function setFlowCaps(FlowConfig[] calldata _flowCaps) external;

    /// @notice Sets the supply cap of a supply through public allocation for some markets.
    /// @dev Doesn't revert if it doesn't change the storage at all.
    function setSupplyCaps(SupplyConfig[] calldata _supplyCaps) external;
}

/// @dev This interface is inherited by PublicAllocator so that function signatures are checked by the compiler.
/// @dev Consider using the IPublicAllocator interface instead of this one.
interface IPublicAllocatorStaticTyping is IPublicAllocatorBase {
    /// @notice Returns (maximum inflow, maximum outflow) through public allocation of a given market.
    function flowCap(Id) external view returns (uint128, uint128);
}

/// @title IPublicAllocator
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @dev Use this interface for PublicAllocator to have access to all the functions with the appropriate function
/// signatures.
interface IPublicAllocator is IPublicAllocatorBase {
    /// @notice Returns the maximum inflow and maximum outflow through public allocation of a given market.
    function flowCap(Id) external view returns (FlowCap memory);
}
