// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;

import {
    FlowCaps,
    FlowCapsConfig,
    SupplyCapConfig,
    Withdrawal,
    MAX_SETTABLE_FLOW_CAP,
    IPublicAllocatorStaticTyping,
    IPublicAllocatorBase
} from "./interfaces/IPublicAllocator.sol";
import {
    Id, IMorpho, IMetaMorpho, MarketAllocation, MarketParams
} from "../lib/metamorpho/src/interfaces/IMetaMorpho.sol";
import {Market} from "../lib/metamorpho/lib/morpho-blue/src/interfaces/IMorpho.sol";

import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import {UtilsLib} from "../lib/metamorpho/lib/morpho-blue/src/libraries/UtilsLib.sol";
import {MarketParamsLib} from "../lib/metamorpho/lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {MorphoBalancesLib} from "../lib/metamorpho/lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";

/// @title MetaMorpho
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Publically callable allocator for a MetaMorpho vault.
contract PublicAllocator is IPublicAllocatorStaticTyping {
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;
    using UtilsLib for uint256;

    /* CONSTANTS */

    /// @inheritdoc IPublicAllocatorBase
    IMorpho public immutable MORPHO;
    /// @inheritdoc IPublicAllocatorBase
    IMetaMorpho public immutable VAULT;

    /* STORAGE */

    /// @inheritdoc IPublicAllocatorBase
    address public owner;
    /// @inheritdoc IPublicAllocatorBase
    uint256 public fee;
    /// @inheritdoc IPublicAllocatorStaticTyping
    mapping(Id => FlowCaps) public flowCaps;
    /// @inheritdoc IPublicAllocatorBase
    mapping(Id => uint256) public supplyCap;

    /* MODIFIER */

    /// @dev Reverts if the caller is not the owner.
    modifier onlyOwner() {
        if (msg.sender != owner) revert ErrorsLib.NotOwner();
        _;
    }

    /* CONSTRUCTOR */

    /// @dev Initializes the contract.
    /// @param newOwner The owner of the contract.
    /// @param vault The address of the MetaMorpho vault.
    constructor(address newOwner, address vault) {
        if (newOwner == address(0)) revert ErrorsLib.ZeroAddress();
        if (vault == address(0)) revert ErrorsLib.ZeroAddress();
        owner = newOwner;
        VAULT = IMetaMorpho(vault);
        MORPHO = VAULT.MORPHO();
    }

    /* PUBLIC */

    /// @inheritdoc IPublicAllocatorBase
    function reallocateTo(Withdrawal[] calldata withdrawals, MarketParams calldata supplyMarketParams)
        external
        payable
    {
        if (msg.value != fee) revert ErrorsLib.IncorrectFee();

        MarketAllocation[] memory allocations = new MarketAllocation[](withdrawals.length + 1);
        Id supplyMarketId = supplyMarketParams.id();
        uint128 totalWithdrawn;

        Id id;
        Id prevId;
        for (uint256 i = 0; i < withdrawals.length; i++) {
            prevId = id;
            id = withdrawals[i].marketParams.id();
            if (Id.unwrap(id) <= Id.unwrap(prevId)) revert ErrorsLib.InconsistentWithdrawals();
            if (Id.unwrap(id) == Id.unwrap(supplyMarketId)) revert ErrorsLib.DepositMarketInWithdrawals();

            MORPHO.accrueInterest(withdrawals[i].marketParams);
            uint256 assets = MORPHO.expectedSupplyAssets(withdrawals[i].marketParams, address(VAULT));
            uint128 withdrawnAssets = withdrawals[i].amount;

            if (flowCaps[id].maxOut < withdrawnAssets) revert ErrorsLib.MaxOutflowExceeded(id);
            if (assets < withdrawnAssets) revert ErrorsLib.NotEnoughSupply(id);

            flowCaps[id].maxIn += withdrawnAssets;
            flowCaps[id].maxOut -= withdrawnAssets;
            allocations[i].marketParams = withdrawals[i].marketParams;
            allocations[i].assets = assets - withdrawnAssets;

            totalWithdrawn += withdrawnAssets;

            emit EventsLib.PublicWithdrawal(id, withdrawnAssets);
        }

        if (flowCaps[supplyMarketId].maxIn < totalWithdrawn) revert ErrorsLib.MaxInflowExceeded(supplyMarketId);

        flowCaps[supplyMarketId].maxIn -= totalWithdrawn;
        flowCaps[supplyMarketId].maxOut += totalWithdrawn;
        allocations[withdrawals.length].marketParams = supplyMarketParams;
        allocations[withdrawals.length].assets = type(uint256).max;

        VAULT.reallocate(allocations);

        if (MORPHO.expectedSupplyAssets(supplyMarketParams, address(VAULT)) > supplyCap[supplyMarketId]) {
            revert ErrorsLib.PublicAllocatorSupplyCapExceeded(supplyMarketId);
        }

        emit EventsLib.PublicReallocateTo(msg.sender, supplyMarketId, totalWithdrawn);
    }

    /* OWNER ONLY */

    /// @inheritdoc IPublicAllocatorBase
    function setOwner(address newOwner) external onlyOwner {
        if (owner == newOwner) revert ErrorsLib.AlreadySet();
        owner = newOwner;
        emit EventsLib.SetOwner(newOwner);
    }

    /// @inheritdoc IPublicAllocatorBase
    function setFee(uint256 newFee) external onlyOwner {
        if (fee == newFee) revert ErrorsLib.AlreadySet();
        fee = newFee;
        emit EventsLib.SetFee(newFee);
    }

    /// @inheritdoc IPublicAllocatorBase
    function transferFee(address payable feeRecipient) external onlyOwner {
        uint256 balance = address(this).balance;
        feeRecipient.transfer(balance);
        emit EventsLib.TransferFee(balance, feeRecipient);
    }

    /// @inheritdoc IPublicAllocatorBase
    function setFlowCaps(FlowCapsConfig[] calldata config) external onlyOwner {
        for (uint256 i = 0; i < config.length; i++) {
            if (config[i].caps.maxIn > MAX_SETTABLE_FLOW_CAP || config[i].caps.maxOut > MAX_SETTABLE_FLOW_CAP) {
                revert ErrorsLib.MaxSettableFlowCapExceeded();
            }
            flowCaps[config[i].id] = config[i].caps;
        }

        emit EventsLib.SetFlowCaps(config);
    }

    /// @inheritdoc IPublicAllocatorBase
    function setSupplyCaps(SupplyCapConfig[] calldata config) external onlyOwner {
        for (uint256 i = 0; i < config.length; i++) {
            supplyCap[config[i].id] = config[i].cap;
        }

        emit EventsLib.SetSupplyCaps(config);
    }
}
