// SPDX-License-Identifier: GPL-2.0-or-later
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
import {EventsLib} from "./libraries/EventsLib.sol";
import {FlowCap, FlowConfig, SupplyConfig, IPublicAllocatorStaticTyping} from "./interfaces/IPublicAllocator.sol";

contract PublicAllocator is Ownable2Step, IPublicAllocatorStaticTyping {
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;
    using UtilsLib for uint256;
    using UtilsLib for uint128;

    /// STORAGE ///

    uint256 public fee;
    IMetaMorpho public immutable VAULT;
    IMorpho public immutable MORPHO;
    mapping(Id => FlowCap) public flowCap;
    mapping(Id => uint256) public supplyCap;

    /// CONSTRUCTOR ///

    constructor(address owner, address vault) Ownable(owner) {
        if (vault == address(0)) {
            revert ErrorsLib.ZeroAddress();
        }
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
            // Do not compute interest twice for every market
            MORPHO.accrueInterest(allocations[i].marketParams);
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
                if (newAssets > supplyCap[id]) {
                    revert ErrorsLib.PublicAllocatorSupplyCapExceeded(id);
                }
                uint128 inflow = (newAssets - assets[i]).toUint128();
                flowCap[id].maxIn -= inflow;
                flowCap[id].maxOut = (flowCap[id].maxOut).saturatingAdd(inflow);
            } else {
                uint128 outflow = (assets[i] - newAssets).toUint128();
                flowCap[id].maxIn = (flowCap[id].maxIn).saturatingAdd(outflow);
                flowCap[id].maxOut -= outflow;
            }
        }

        emit EventsLib.PublicReallocate(_msgSender(), msg.value);
    }

    /// OWNER ONLY ///

    function setFee(uint256 _fee) external onlyOwner {
        if (fee == _fee) {
            revert ErrorsLib.AlreadySet();
        }
        fee = _fee;
        emit EventsLib.SetFee(_fee);
    }

    function transferFee(address payable feeRecipient) external onlyOwner {
        uint256 balance = address(this).balance;
        if (address(this).balance > 0) {
            feeRecipient.transfer(address(this).balance);
            emit EventsLib.SetFee(balance);
        }
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
