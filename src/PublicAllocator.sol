// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;

import {
    Id, IMorpho, IMetaMorpho, MarketAllocation, MarketParams
} from "../lib/metamorpho/src/interfaces/IMetaMorpho.sol";

import {MarketParamsLib} from "../lib/metamorpho/lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {MorphoBalancesLib} from "../lib/metamorpho/lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";

import {Market} from "../lib/metamorpho/lib/morpho-blue/src/interfaces/IMorpho.sol";

import {UtilsLib} from "../lib/metamorpho/lib/morpho-blue/src/libraries/UtilsLib.sol";

import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import {
    FlowCap,
    FlowConfig,
    SupplyConfig,
    Withdrawal,
    MAX_SETTABLE_FLOW_CAP,
    IPublicAllocatorStaticTyping,
    IPublicAllocatorBase
} from "./interfaces/IPublicAllocator.sol";

/// @title MetaMorpho
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Publically callable allocator for a MetaMorpho vault.
contract PublicAllocator is IPublicAllocatorStaticTyping {
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;
    using UtilsLib for uint256;

    /// CONSTANTS ///

    /// @inheritdoc IPublicAllocatorBase
    address public immutable OWNER;

    /// @inheritdoc IPublicAllocatorBase
    IMorpho public immutable MORPHO;

    /// @inheritdoc IPublicAllocatorBase
    IMetaMorpho public immutable VAULT;

    /// STORAGE ///

    /// @inheritdoc IPublicAllocatorBase
    uint256 public fee;

    /// @inheritdoc IPublicAllocatorStaticTyping
    mapping(Id => FlowCap) public flowCap;

    /// @inheritdoc IPublicAllocatorBase
    mapping(Id => uint256) public supplyCap;

    /// MODIFIER ///

    /// @dev Reverts if the caller is not the owner.
    modifier onlyOwner() {
        if (msg.sender != OWNER) revert ErrorsLib.NotOwner();
        _;
    }

    /// CONSTRUCTOR ///

    /// @dev Initializes the contract.
    /// @param newOwner The owner of the contract.
    /// @param vault The address of the MetaMorpho vault.
    constructor(address newOwner, address vault) {
        if (newOwner == address(0)) revert ErrorsLib.ZeroAddress();
        if (vault == address(0)) revert ErrorsLib.ZeroAddress();
        OWNER = newOwner;
        VAULT = IMetaMorpho(vault);
        MORPHO = VAULT.MORPHO();
    }

    /// PUBLIC ///

    /// @inheritdoc IPublicAllocatorBase
    function withdrawTo(Withdrawal[] calldata withdrawals, MarketParams calldata depositMarketParams)
        external
        payable
    {
        if (msg.value != fee) revert ErrorsLib.IncorrectFee();

        MarketAllocation[] memory allocations = new MarketAllocation[](withdrawals.length + 1);
        Id depositMarketId = depositMarketParams.id();
        uint128 totalWithdrawn;

        for (uint256 i = 0; i < withdrawals.length; i++) {
            Id id = withdrawals[i].marketParams.id();

            // Revert if the market is elsewhere in the list, or is the deposit market.
            for (uint256 j = i + 1; j < withdrawals.length; j++) {
                if (Id.unwrap(id) == Id.unwrap(withdrawals[j].marketParams.id())) {
                    revert ErrorsLib.InconsistentWithdrawTo();
                }
            }
            if (Id.unwrap(id) == Id.unwrap(depositMarketId)) revert ErrorsLib.InconsistentWithdrawTo();

            uint128 withdrawnAssets = withdrawals[i].amount;
            totalWithdrawn += withdrawnAssets;

            MORPHO.accrueInterest(withdrawals[i].marketParams);
            uint256 assets = MORPHO.expectedSupplyAssets(withdrawals[i].marketParams, address(VAULT));

            allocations[i].marketParams = withdrawals[i].marketParams;
            allocations[i].assets = assets - withdrawnAssets;
            flowCap[id].maxIn += withdrawnAssets;
            flowCap[id].maxOut -= withdrawnAssets;

            emit EventsLib.PublicWithdrawal(id, withdrawnAssets);
        }

        allocations[withdrawals.length].marketParams = depositMarketParams;
        allocations[withdrawals.length].assets = type(uint256).max;
        flowCap[depositMarketId].maxIn -= totalWithdrawn;
        flowCap[depositMarketId].maxOut += totalWithdrawn;

        VAULT.reallocate(allocations);

        if (MORPHO.expectedSupplyAssets(depositMarketParams, address(VAULT)) > supplyCap[depositMarketId]) {
            revert ErrorsLib.PublicAllocatorSupplyCapExceeded(depositMarketId);
        }

        emit EventsLib.PublicReallocateTo(msg.sender, depositMarketId, totalWithdrawn);
    }

    /// OWNER ONLY ///

    /// @inheritdoc IPublicAllocatorBase
    function setFee(uint256 _fee) external onlyOwner {
        if (fee == _fee) revert ErrorsLib.AlreadySet();
        fee = _fee;
        emit EventsLib.SetFee(_fee);
    }

    /// @inheritdoc IPublicAllocatorBase
    function transferFee(address payable feeRecipient) external onlyOwner {
        uint256 balance = address(this).balance;
        feeRecipient.transfer(balance);
        emit EventsLib.TransferFee(balance, feeRecipient);
    }

    /// @inheritdoc IPublicAllocatorBase
    function setFlowCaps(FlowConfig[] calldata flowCaps) external onlyOwner {
        for (uint256 i = 0; i < flowCaps.length; i++) {
            if (flowCaps[i].cap.maxIn > MAX_SETTABLE_FLOW_CAP || flowCaps[i].cap.maxOut > MAX_SETTABLE_FLOW_CAP) {
                revert ErrorsLib.MaxSettableFlowCapExceeded();
            }
            flowCap[flowCaps[i].id] = flowCaps[i].cap;
        }

        emit EventsLib.SetFlowCaps(flowCaps);
    }

    /// @inheritdoc IPublicAllocatorBase
    function setSupplyCaps(SupplyConfig[] calldata supplyCaps) external onlyOwner {
        for (uint256 i = 0; i < supplyCaps.length; i++) {
            supplyCap[supplyCaps[i].id] = supplyCaps[i].cap;
        }

        emit EventsLib.SetSupplyCaps(supplyCaps);
    }
}
