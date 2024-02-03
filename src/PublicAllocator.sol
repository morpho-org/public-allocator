// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IMetaMorpho, MarketAllocation} from "../lib/metamorpho/src/interfaces/IMetaMorpho.sol";

contract PublicAllocator {

    /// STORAGE ///

    address public owner;
    IMetaMorpho public vault;

    /// CONSTRUCTOR ///

    constructor(address newOwner, IMetaMorpho newVault) {
        owner = newOwner;
        vault = newVault;
    }

    /// PUBLIC ///

    function reallocate(MarketAllocation[] calldata allocations) external {
        vault.reallocate(allocations);
    }
}
