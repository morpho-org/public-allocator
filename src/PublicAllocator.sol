// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {
    Id, IMorpho, IMetaMorpho, MarketAllocation, MarketParams
} from "../lib/metamorpho/src/interfaces/IMetaMorpho.sol";

import {MarketParamsLib} from "../lib/metamorpho/lib/morpho-blue/src/libraries/MarketParamsLib.sol";

import {MorphoLib} from "../lib/metamorpho/lib/morpho-blue/src/libraries/periphery/MorphoLib.sol";

import {MorphoBalancesLib} from "../lib/metamorpho/lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";

import {SharesMathLib} from "../lib/metamorpho/lib/morpho-blue/src/libraries/SharesMathLib.sol";

import {Market} from "../lib/metamorpho/lib/morpho-blue/src/interfaces/IMorpho.sol";
import {UtilsLib} from "./libraries/UtilsLib.sol";
import {Ownable2Step, Ownable} from "../lib/metamorpho/lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";

import {Multicall} from "../lib/metamorpho/lib/openzeppelin-contracts/contracts/utils/Multicall.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {FlowCaps, FlowConfig, IPublicAllocatorStaticTyping} from "./interfaces/IPublicAllocator.sol";

contract PublicAllocator is Ownable2Step, Multicall, IPublicAllocatorStaticTyping {
    using MorphoLib for IMorpho;
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;
    using UtilsLib for uint256;
    using UtilsLib for uint128;

    /// STORAGE ///

    uint256 fee;
    IMetaMorpho public immutable VAULT;
    IMorpho public immutable MORPHO;
    mapping(Id => FlowCaps) public flowCaps;
    mapping(Id => uint256) public supplyCaps;

    /// CONSTRUCTOR ///

    constructor(address owner, address vault) Ownable(owner) {
        if (vault == address(0)) revert ErrorsLib.ZeroAddress();
        VAULT = IMetaMorpho(vault);
        MORPHO = VAULT.MORPHO();
    }

    /// PUBLIC ///

    function reallocate(MarketAllocation[] calldata allocations) external payable {
        if (msg.value < fee) {
            revert ErrorsLib.FeeTooLow();
        }

        uint256[] memory shares = new uint256[](allocations.length);
        for (uint256 i = 0; i < allocations.length; ++i) {
            shares[i] = MORPHO.supplyShares(allocations[i].marketParams.id(), address(VAULT));
        }

        VAULT.reallocate(allocations);

        Market memory market;
        for (uint256 i = 0; i < allocations.length; ++i) {
            Id id = allocations[i].marketParams.id();
            market = MORPHO.market(id);
            uint256 newShares = MORPHO.supplyShares(id, address(VAULT));
            if (newShares >= shares[i]) {
                // Withdrawing small enough amounts when the cap is already exceeded can result in the error below
                if (newShares.toAssetsUp(market.totalSupplyAssets, market.totalSupplyShares) > supplyCaps[id]) {
                    revert ErrorsLib.PublicAllocatorSupplyCapExceeded(id);
                }
                uint128 inflow =
                    (newShares - shares[i]).toAssetsUp(market.totalSupplyAssets, market.totalSupplyShares).toUint128();
                flowCaps[id].maxIn -= inflow;
                flowCaps[id].maxOut = (flowCaps[id].maxOut).saturatingAdd(inflow);
            } else {
                uint128 outflow =
                    (shares[i] - newShares).toAssetsUp(market.totalSupplyAssets, market.totalSupplyShares).toUint128();
                flowCaps[id].maxIn = (flowCaps[id].maxIn).saturatingAdd(outflow);
                flowCaps[id].maxOut -= outflow;
            }
        }
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
