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

    /* STORAGE */

    /// @inheritdoc IPublicAllocatorBase
    mapping(address => address) public owner;
    /// @inheritdoc IPublicAllocatorBase
    mapping(address => uint256) public fee;
    /// Accrued fee.
    mapping(address => uint256) public accruedFee;
    /// @inheritdoc IPublicAllocatorStaticTyping
    mapping(address => mapping(Id => FlowCaps)) public flowCaps;
    /// @inheritdoc IPublicAllocatorBase
    mapping(address => mapping(Id => uint256)) public supplyCap;

    /* MODIFIER */

    /// @dev Reverts if the caller is not the owner.
    modifier onlyOwner(address vault) {
        if (msg.sender != owner[vault] && msg.sender != IMetaMorpho(vault).owner()) revert ErrorsLib.NotOwner();
        _;
    }

    /* CONSTRUCTOR */

    /// @dev Initializes the contract.
    constructor(address morpho) {
        MORPHO = IMorpho(morpho);
    }

    /* PUBLIC */

    /// @inheritdoc IPublicAllocatorBase
    function reallocateTo(address vault, Withdrawal[] calldata withdrawals, MarketParams calldata supplyMarketParams)
        external
        payable
    {
        if (msg.value != fee[vault]) revert ErrorsLib.IncorrectFee();
        accruedFee[vault] += msg.value;

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
            uint256 assets = MORPHO.expectedSupplyAssets(withdrawals[i].marketParams, address(vault));
            uint128 withdrawnAssets = withdrawals[i].amount;

            if (flowCaps[vault][id].maxOut < withdrawnAssets) revert ErrorsLib.MaxOutflowExceeded(id);
            if (assets < withdrawnAssets) revert ErrorsLib.NotEnoughSupply(id);

            flowCaps[vault][id].maxIn += withdrawnAssets;
            flowCaps[vault][id].maxOut -= withdrawnAssets;
            allocations[i].marketParams = withdrawals[i].marketParams;
            allocations[i].assets = assets - withdrawnAssets;

            totalWithdrawn += withdrawnAssets;

            emit EventsLib.PublicWithdrawal(id, withdrawnAssets);
        }

        if (flowCaps[vault][supplyMarketId].maxIn < totalWithdrawn) revert ErrorsLib.MaxInflowExceeded(supplyMarketId);

        flowCaps[vault][supplyMarketId].maxIn -= totalWithdrawn;
        flowCaps[vault][supplyMarketId].maxOut += totalWithdrawn;
        allocations[withdrawals.length].marketParams = supplyMarketParams;
        allocations[withdrawals.length].assets = type(uint256).max;

        IMetaMorpho(vault).reallocate(allocations);

        if (MORPHO.expectedSupplyAssets(supplyMarketParams, vault) > supplyCap[vault][supplyMarketId]) {
            revert ErrorsLib.PublicAllocatorSupplyCapExceeded(supplyMarketId);
        }

        emit EventsLib.PublicReallocateTo(msg.sender, supplyMarketId, totalWithdrawn);
    }

    /* OWNER ONLY */

    /// @inheritdoc IPublicAllocatorBase
    function setOwner(address vault, address newOwner) external onlyOwner(vault) {
        if (owner[vault] == newOwner) revert ErrorsLib.AlreadySet();
        owner[vault] = newOwner;
        emit EventsLib.SetOwner(vault, newOwner);
    }

    /// @inheritdoc IPublicAllocatorBase
    function setFee(address vault, uint256 newFee) external onlyOwner(vault) {
        if (fee[vault] == newFee) revert ErrorsLib.AlreadySet();
        fee[vault] = newFee;
        emit EventsLib.SetFee(vault, newFee);
    }

    /// @inheritdoc IPublicAllocatorBase
    function transferFee(address vault, address payable feeRecipient) external onlyOwner(vault) {
        uint256 claimed = accruedFee[vault];
        accruedFee[vault] = 0;
        feeRecipient.transfer(claimed);
        emit EventsLib.TransferFee(claimed, feeRecipient);
    }

    /// @inheritdoc IPublicAllocatorBase
    function setFlowCaps(address vault, FlowCapsConfig[] calldata config) external onlyOwner(vault) {
        for (uint256 i = 0; i < config.length; i++) {
            if (config[i].caps.maxIn > MAX_SETTABLE_FLOW_CAP || config[i].caps.maxOut > MAX_SETTABLE_FLOW_CAP) {
                revert ErrorsLib.MaxSettableFlowCapExceeded();
            }
            flowCaps[vault][config[i].id] = config[i].caps;
        }

        emit EventsLib.SetFlowCaps(config);
    }

    /// @inheritdoc IPublicAllocatorBase
    function setSupplyCaps(address vault, SupplyCapConfig[] calldata config) external onlyOwner(vault) {
        for (uint256 i = 0; i < config.length; i++) {
            supplyCap[vault][config[i].id] = config[i].cap;
        }

        emit EventsLib.SetSupplyCaps(config);
    }
}
