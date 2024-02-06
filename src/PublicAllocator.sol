// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {Id, IMorpho, IMetaMorpho, MarketAllocation,MarketParams} from "../lib/metamorpho/src/interfaces/IMetaMorpho.sol";
import {MarketParamsLib, MorphoLib,MorphoBalancesLib,SharesMathLib,Market} from "../lib/metamorpho/src/MetaMorpho.sol";
import {Ownable2Step, Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {FlowCaps, FlowConfig, IPublicAllocatorStaticTyping} from "./interfaces/IPublicAllocator.sol";

contract PublicAllocator is Ownable2Step, IPublicAllocatorStaticTyping {
    using MorphoLib for IMorpho;
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;

    /// STORAGE ///

    uint fee;
    IMetaMorpho public immutable VAULT;
    IMorpho public immutable MORPHO;
    mapping(Id => int) public flows;
    mapping(Id => FlowCaps) public flowCaps;
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

        uint[] memory shares = new uint[](allocations.length);
        for (uint256 i = 0; i < allocations.length; ++i) {
            shares[i] = MORPHO.supplyShares(allocations[i].marketParams.id(), address(VAULT));
        }

        VAULT.reallocate(allocations);

        Market memory market;
        for (uint256 i = 0; i < allocations.length; ++i) {
            Id id = allocations[i].marketParams.id();
            market = MORPHO.market(id);
            uint newShares = MORPHO.supplyShares(id, address(VAULT));
            if (newShares >= shares[i]) {
                flows[id] += int((newShares - shares[i]).toAssetsUp(market.totalSupplyAssets,market.totalSupplyShares));
                if (flows[id] > int(uint(flowCaps[id].inflow))) {
                    revert ErrorsLib.InflowCapExceeded(id);
                }
            } else {
                flows[id] -= int((shares[i] - newShares).toAssetsUp(market.totalSupplyAssets,market.totalSupplyShares));
                if (flows[id] < -int(uint(flowCaps[id].outflow))) {
                    revert ErrorsLib.OutflowCapExceeded(id);
                }
            }
        }
            
    }

    /// OWNER ONLY ///

    function setFee(uint _fee) external onlyOwner {
        fee = _fee;
    }

    function transferFee(address feeRecipient) external onlyOwner {
        if (address(this).balance > 0) {
            (bool success,) = feeRecipient.call{value:address(this).balance}("");
            if (!success) {
                revert ErrorsLib.FeeTransferFail();
            }
        }
    }

    // Set flow caps and optionally reset a flow.
    // Flows are rounded up from shares at every reallocation, so small errors may accumulate.
    function setFlows(FlowConfig[] calldata flowConfigs) external onlyOwner {
        FlowConfig memory flowConfig;
        for (uint i = 0; i < flowConfigs.length; ++i) {
            flowConfig = flowConfigs[i];
            Id id = flowConfig.id;

            flowCaps[id] = flowConfig.caps;

            if (flowConfig.resetFlow) {
                flows[id] = 0;
            }
        }
    }
}
