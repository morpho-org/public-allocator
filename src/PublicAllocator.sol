// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;

import "forge-std/console2.sol";
import {
    Id, IMorpho, IMetaMorpho, MarketAllocation, MarketParams
} from "../lib/metamorpho/src/interfaces/IMetaMorpho.sol";

import {MarketParamsLib} from "../lib/metamorpho/lib/morpho-blue/src/libraries/MarketParamsLib.sol";

import {MorphoLib} from "../lib/metamorpho/lib/morpho-blue/src/libraries/periphery/MorphoLib.sol";

import {MorphoBalancesLib} from "../lib/metamorpho/lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";

import {SharesMathLib} from "../lib/metamorpho/lib/morpho-blue/src/libraries/SharesMathLib.sol";

import {Market} from "../lib/metamorpho/lib/morpho-blue/src/interfaces/IMorpho.sol";
import {UtilsLib} from "./libraries/UtilsLib.sol";

import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import {
    FlowCap,
    FlowConfig,
    SupplyConfig,
    Withdrawal,
    IPublicAllocatorStaticTyping
} from "./interfaces/IPublicAllocator.sol";

contract PublicAllocator is IPublicAllocatorStaticTyping {
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;
    using UtilsLib for uint256;
    using UtilsLib for uint128;

    /// CONSTANTS ///

    address public immutable OWNER;
    IMorpho public immutable MORPHO;
    IMetaMorpho public immutable VAULT;

    /// STORAGE ///

    uint256 public fee;
    mapping(Id => FlowCap) public flowCap;
    mapping(Id => uint256) public supplyCap;

    /// MODIFIER ///

    modifier onlyOwner() {
        if (msg.sender != OWNER) revert ErrorsLib.NotOwner();
        _;
    }

    /// CONSTRUCTOR ///

    constructor(address newOwner, address vault) {
        if (newOwner == address(0)) revert ErrorsLib.ZeroAddress();
        if (vault == address(0)) revert ErrorsLib.ZeroAddress();
        OWNER = newOwner;
        VAULT = IMetaMorpho(vault);
        MORPHO = VAULT.MORPHO();
    }

    /// PUBLIC ///

    function withdrawTo(Withdrawal[] calldata withdrawals, MarketParams calldata depositMarketParams)
        external
        payable
    {
        if (msg.value != fee) revert ErrorsLib.IncorrectFee(msg.value);

        MarketAllocation[] memory allocations = new MarketAllocation[](withdrawals.length + 1);

        uint128 totalWithdrawn;

        for (uint256 i = 0; i < withdrawals.length; ++i) {
            allocations[i].marketParams = withdrawals[i].marketParams;
            Id id = withdrawals[i].marketParams.id();
            uint256 assets = MORPHO.expectedSupplyAssets(withdrawals[i].marketParams, address(VAULT));
            uint128 withdrawnAssets = withdrawals[i].amount;
            // Clamp at 0 if withdrawnAssets is too big
            if (withdrawnAssets > assets) {
                withdrawnAssets = assets.toUint128();
            }

            totalWithdrawn += withdrawnAssets;
            allocations[i].assets = assets - withdrawnAssets;
            flowCap[id].maxIn = (flowCap[id].maxIn).saturatingAdd(withdrawnAssets);
            flowCap[id].maxOut -= withdrawnAssets;
            emit EventsLib.PublicWithdrawal(id, withdrawnAssets);
        }

        Id depositMarketId = depositMarketParams.id();

        MORPHO.accrueInterest(depositMarketParams);
        uint totalSupplyAssetsBefore = MORPHO.totalSupplyAssets(depositMarketId);

        allocations[withdrawals.length].marketParams = depositMarketParams;
        allocations[withdrawals.length].assets = type(uint).max;

        VAULT.reallocate(allocations);

        Market memory depositMarket = MORPHO.market(depositMarketId);

        // Protect against duplicates with nonzero amounts in withdrawals
        if (depositMarket.totalSupplyAssets - totalSupplyAssetsBefore != totalWithdrawn) {
            revert ErrorsLib.InconsistentWithdrawTo(withdrawals,depositMarketParams);
        }

        uint256 vaultSupplyInMarket = MORPHO.supplyShares(depositMarketId,address(VAULT)).toAssetsDown(depositMarket.totalSupplyAssets,depositMarket.totalSupplyShares);

        if (vaultSupplyInMarket > supplyCap[depositMarketId]) revert ErrorsLib.PublicAllocatorSupplyCapExceeded(depositMarketId);

        flowCap[depositMarketId].maxIn -= totalWithdrawn;
        flowCap[depositMarketId].maxOut = (flowCap[depositMarketId].maxOut).saturatingAdd(totalWithdrawn);

        emit EventsLib.PublicReallocateTo(msg.sender, fee, depositMarketId, totalWithdrawn);
    }

    /// OWNER ONLY ///

    function setFee(uint256 _fee) external onlyOwner {
        if (fee == _fee) revert ErrorsLib.AlreadySet();
        fee = _fee;
        emit EventsLib.SetFee(_fee);
    }

    function transferFee(address payable feeRecipient) external onlyOwner {
        uint256 balance = address(this).balance;
        feeRecipient.transfer(balance);
        emit EventsLib.TransferFee(balance);
    }

    // Set flow cap
    // Doesn't revert if it doesn't change the storage at all
    function setFlowCaps(FlowConfig[] calldata flowCaps) external onlyOwner {
        for (uint256 i = 0; i < flowCaps.length; ++i) {
            flowCap[flowCaps[i].id] = flowCaps[i].cap;
        }

        emit EventsLib.SetFlowCaps(flowCaps);
    }

    // Set supply cap. Public reallocation will not be able to increase supply if it ends above its cap.
    // Doesn't revert if it doesn't change the storage at all
    function setSupplyCaps(SupplyConfig[] calldata supplyCaps) external onlyOwner {
        for (uint256 i = 0; i < supplyCaps.length; ++i) {
            supplyCap[supplyCaps[i].id] = supplyCaps[i].cap;
        }

        emit EventsLib.SetSupplyCaps(supplyCaps);
    }
}
