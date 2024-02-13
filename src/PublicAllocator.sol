// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {
    Id, IMorpho, IMetaMorpho, MarketAllocation, MarketParams
} from "../lib/metamorpho/src/interfaces/IMetaMorpho.sol";
import {
    MarketParamsLib,
    MorphoLib,
    MorphoBalancesLib,
    SharesMathLib,
    Market,
    UtilsLib
} from "../lib/metamorpho/src/MetaMorpho.sol";
import {MorphoBalancesLib} from "../lib/metamorpho/lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {Ownable2Step, Ownable} from "../lib/metamorpho/lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {Multicall} from "../lib/metamorpho/lib/openzeppelin-contracts/contracts/utils/Multicall.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {FlowCaps, FlowConfig, Withdrawal, IPublicAllocatorStaticTyping} from "./interfaces/IPublicAllocator.sol";

contract PublicAllocator is Ownable2Step, Multicall, IPublicAllocatorStaticTyping {
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;
    using UtilsLib for uint256;

    /// STORAGE ///

    uint256 fee;
    IMetaMorpho public immutable VAULT;
    IMorpho public immutable MORPHO;
    mapping(Id => FlowCaps) public flowCaps;
    mapping(Id => uint256) public supplyCaps;
    // using IMorpho

    /// CONSTRUCTOR ///

    constructor(address owner, address vault) Ownable(owner) {
        if (vault == address(0)) revert ErrorsLib.ZeroAddress();
        VAULT = IMetaMorpho(vault);
        MORPHO = VAULT.MORPHO();
    }

    /// PUBLIC ///

    function withdrawTo(Withdrawal[] calldata withdrawals, MarketParams calldata depositMarketParams) external payable {
        if (msg.value < fee) {
            revert ErrorsLib.FeeTooLow();
        }

        MarketAllocation[] memory allocations = new MarketAllocation[](withdrawals.length+1);
        allocations[withdrawals.length].marketParams = depositMarketParams;
        allocations[withdrawals.length].assets = type(uint).max;

        uint128 totalWithdrawn;

        for (uint256 i = 0; i < withdrawals.length; ++i) {
            allocations[i].marketParams = withdrawals[i].marketParams;
            Id id = withdrawals[i].marketParams.id();
            uint assets = MORPHO.expectedSupplyAssets(withdrawals[i].marketParams,address(VAULT));
            uint128 withdrawnAssets = withdrawals[i].amount;
            // Clamp at 0 if withdrawnAssets is too big
            if (withdrawnAssets > assets) {
                withdrawnAssets = assets.toUint128();
            }

            totalWithdrawn += withdrawnAssets;
            allocations[i].assets = assets - withdrawnAssets;
            flowCaps[id].maxIn += withdrawnAssets;
            flowCaps[id].maxOut -= withdrawnAssets;
        }

        VAULT.reallocate(allocations);

        Id depositMarketId = depositMarketParams.id();
        uint depositAssets = MORPHO.expectedSupplyAssets(depositMarketParams,address(VAULT));
        if (depositAssets > supplyCaps[depositMarketId]) {
            revert ErrorsLib.PublicAllocatorSupplyCapExceeded(depositMarketId);
        }
        flowCaps[depositMarketId].maxIn -= totalWithdrawn;
        flowCaps[depositMarketId].maxOut += totalWithdrawn;

    }

    /// OWNER ONLY ///

    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }

    function transferFee(address feeRecipient) external onlyOwner {
        if (address(this).balance > 0) {
            (bool success,) = feeRecipient.call{value: address(this).balance}("");
            if (!success) {
                revert ErrorsLib.FeeTransferFail();
            }
        }
    }

    // Set flow cap
    // Flows are rounded up from shares at every reallocation, so small errors may accumulate.
    function setFlow(FlowConfig calldata flowConfig) external onlyOwner {
        flowCaps[flowConfig.id] = flowConfig.caps;
    }

    // Set supply cap. Public reallocation will not be able to increase supply if it ends above its cap.
    function setCap(Id id, uint256 supplyCap) external onlyOwner {
        supplyCaps[id] = supplyCap;
    }
}
