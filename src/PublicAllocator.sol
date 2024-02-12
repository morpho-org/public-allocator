// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {
    Id, IMorpho, IMetaMorpho, MarketAllocation, MarketParams
} from "../lib/metamorpho/src/interfaces/IMetaMorpho.sol";
import {
    MarketParamsLib, MorphoLib, MorphoBalancesLib, SharesMathLib, Market
} from "../lib/metamorpho/src/MetaMorpho.sol";
import {Ownable2Step, Ownable} from "../lib/metamorpho/lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {Multicall} from "../lib/metamorpho/lib/openzeppelin-contracts/contracts/utils/Multicall.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {FlowCaps, FlowConfig, IPublicAllocatorStaticTyping} from "./interfaces/IPublicAllocator.sol";

contract PublicAllocator is Ownable2Step, Multicall, IPublicAllocatorStaticTyping {
    using MorphoLib for IMorpho;
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;

    /// STORAGE ///

    uint256 fee;
    IMetaMorpho public immutable VAULT;
    IMorpho public immutable MORPHO;
    mapping(Id => int256) public flows;
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
                if (newShares.toAssetsUp(market.totalSupplyAssets,market.totalSupplyShares) > supplyCaps[id]) {
                    revert ErrorsLib.PublicAllocatorSupplyCapExceeded(id);
                }
                flows[id] +=
                    int256((newShares - shares[i]).toAssetsUp(market.totalSupplyAssets, market.totalSupplyShares));
                if (flows[id] > int256(uint256(flowCaps[id].inflow))) {
                    revert ErrorsLib.InflowCapExceeded(id);
                }
            } else {
                flows[id] -=
                    int256((shares[i] - newShares).toAssetsUp(market.totalSupplyAssets, market.totalSupplyShares));
                if (flows[id] < -int256(uint256(flowCaps[id].outflow))) {
                    revert ErrorsLib.OutflowCapExceeded(id);
                }
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

    // Set flow caps and optionally reset a flow.
    // Flows are rounded up from shares at every reallocation, so small errors may accumulate.
    function setFlow(FlowConfig calldata flowConfig) external onlyOwner {
        flowCaps[flowConfig.id] = flowConfig.caps;

        if (flowConfig.resetFlow) {
            flows[flowConfig.id] = 0;
        }
    }

    // Set supply cap. Public reallocation will not be able to increase supply if it ends above its cap. 
    function setCap(Id id, uint supplyCap) external onlyOwner {
        supplyCaps[id] = supplyCap;
    }
}
