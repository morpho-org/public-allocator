// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../lib/metamorpho/test/forge/helpers/IntegrationTest.sol";
import "../src/PublicAllocator.sol";

uint256 constant CAP2 = 100e18;
uint256 constant INITIAL_DEPOSIT = 4 * CAP2;

contract PublicAllocatorTest is IntegrationTest {
    PublicAllocator public publicAllocator;    
    MarketAllocation[] internal allocations;

    function setUp() public override {
        super.setUp();

        publicAllocator = new PublicAllocator(address(this), vault);
        vm.prank(OWNER);
        vault.setIsAllocator(address(publicAllocator), true);

        loanToken.setBalance(SUPPLIER, INITIAL_DEPOSIT);

        vm.prank(SUPPLIER);
        vault.deposit(INITIAL_DEPOSIT, ONBEHALF);

        _setCap(allMarkets[0], CAP2);
        _setCap(allMarkets[1], CAP2);
        _setCap(allMarkets[2], CAP2);

        _sortSupplyQueueIdleLast();
    }

    function testOwner() public {
        assertEq(publicAllocator.owner(), address(this));
    }

    function testReallocate() public {
        allocations.push(MarketAllocation(allMarkets[0], 0));
        allocations.push(MarketAllocation(allMarkets[1], 0));
        allocations.push(MarketAllocation(allMarkets[2], 0));
        allocations.push(MarketAllocation(idleParams, type(uint256).max));
        
        publicAllocator.reallocate(allocations);
    }
}
