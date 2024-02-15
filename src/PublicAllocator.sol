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

import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {FlowCaps, FlowConfig, SupplyConfig, IPublicAllocatorStaticTyping} from "./interfaces/IPublicAllocator.sol";

contract PublicAllocator is Ownable2Step, IPublicAllocatorStaticTyping {
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;
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

        uint256[] memory assets = new uint256[](allocations.length);
        for (uint256 i = 0; i < allocations.length; ++i) {
            assets[i] = MORPHO.expectedSupplyAssets(allocations[i].marketParams, address(VAULT));
        }

        VAULT.reallocate(allocations);

        MarketParams memory marketParams;
        Market memory market;
        for (uint256 i = 0; i < allocations.length; ++i) {
            marketParams = allocations[i].marketParams;
            Id id = marketParams.id();
            market = MORPHO.market(id);
            uint256 newAssets = MORPHO.expectedSupplyAssets(marketParams, address(VAULT));
            if (newAssets >= assets[i]) {
                if (newAssets > supplyCaps[id]) {
                    revert ErrorsLib.PublicAllocatorSupplyCapExceeded(id);
                }
                uint128 inflow = (newAssets - assets[i]).toUint128();
                flowCaps[id].maxIn -= inflow;
                flowCaps[id].maxOut = (flowCaps[id].maxOut).saturatingAdd(inflow);
            } else {
                uint128 outflow = (assets[i] - newAssets).toUint128();
                flowCaps[id].maxIn = (flowCaps[id].maxIn).saturatingAdd(outflow);
                flowCaps[id].maxOut -= outflow;
            }
        }
    }

    /// OWNER ONLY ///

    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }

    function transferFee(address payable feeRecipient) external onlyOwner {
        if (address(this).balance > 0) {
            feeRecipient.transfer(address(this).balance);
        }
    }

    // Set flow cap
    // Flows are rounded up from shares at every reallocation, so small errors may accumulate.
    function setFlowCaps(FlowConfig[] calldata _flowCaps) external onlyOwner {
        for (uint i = 0; i < _flowCaps.length; ++i) {
            flowCaps[_flowCaps[i].id] = _flowCaps[i].caps;
        }
    }

    // Set supply cap. Public reallocation will not be able to increase supply if it ends above its cap.
    function setSupplyCaps(SupplyConfig[] calldata _supplyCaps) external onlyOwner {
        for (uint i = 0; i < _supplyCaps.length; ++i) {
            supplyCaps[_supplyCaps[i].id] = _supplyCaps[i].cap;
        }
    }
}
