// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../lib/metamorpho/test/forge/helpers/IntegrationTest.sol";
import {PublicAllocator, FlowConfig, FlowCaps} from "../src/PublicAllocator.sol";
import {ErrorsLib as PAErrorsLib} from "../src/libraries/ErrorsLib.sol";
import {UtilsLib} from "../lib/metamorpho/lib/morpho-blue/src/libraries/UtilsLib.sol";
import {IPublicAllocator} from "../src/interfaces/IPublicAllocator.sol";

uint256 constant CAP2 = 100e18;
uint256 constant INITIAL_DEPOSIT = 4 * CAP2;

contract CantReceive {}

contract PublicAllocatorTest is IntegrationTest {
    IPublicAllocator public publicAllocator;
    MarketAllocation[] internal allocations;

    using MarketParamsLib for MarketParams;

    function setUp() public override {
        super.setUp();

        publicAllocator = IPublicAllocator(address(new PublicAllocator(address(OWNER), address(vault))));
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
        assertEq(publicAllocator.owner(), address(OWNER));
    }

    function testReallocateCapZeroOutflowByDefault(uint256 flow) public {
        flow = uint128(bound(flow, 0, CAP2));
        vm.assume(flow != 0);
        allocations.push(MarketAllocation(idleParams, INITIAL_DEPOSIT - flow));
        allocations.push(MarketAllocation(allMarkets[0], flow));
        vm.expectRevert(abi.encodeWithSelector(PAErrorsLib.OutflowCapExceeded.selector, idleParams.id()));
        publicAllocator.reallocate(allocations);
    }

    function testReallocateCapZeroInflowByDefault(uint128 flow) public {
        flow = uint128(bound(flow, 0, CAP2));
        vm.assume(flow != 0);
        deal(address(loanToken), address(vault), flow);
        allocations.push(MarketAllocation(allMarkets[0], flow));
        allocations.push(MarketAllocation(idleParams, INITIAL_DEPOSIT - flow));
        vm.expectRevert(abi.encodeWithSelector(PAErrorsLib.InflowCapExceeded.selector, allMarkets[0].id()));
        publicAllocator.reallocate(allocations);
    }

    function testConfigureFlowAccess(address sender) public {
        vm.assume(sender != OWNER);
        vm.prank(sender);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, sender));
        publicAllocator.setFlow(FlowConfig(idleParams.id(), FlowCaps(0, 0), false));
    }

    function testTransferFeeAccess(address sender, address recipient) public {
        vm.assume(sender != OWNER);
        vm.prank(sender);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, sender));
        publicAllocator.transferFee(recipient);
    }

    function testSetFeeAccess(address sender, uint256 fee) public {
        vm.assume(sender != OWNER);
        vm.prank(sender);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, sender));
        publicAllocator.setFee(fee);
    }

    function testReallocateNetting(uint128 flow) public {
        flow = uint128(bound(flow, 0, CAP2));
        vm.assume(flow != 0);

        vm.prank(OWNER);
        publicAllocator.setFlow(FlowConfig(idleParams.id(), FlowCaps(flow, 0), false));
        vm.prank(OWNER);
        publicAllocator.setFlow(FlowConfig(allMarkets[0].id(), FlowCaps(0, flow), false));

        allocations.push(MarketAllocation(idleParams, INITIAL_DEPOSIT - flow));
        allocations.push(MarketAllocation(allMarkets[0], flow));
        publicAllocator.reallocate(allocations);

        delete allocations;
        allocations.push(MarketAllocation(allMarkets[0], 0));
        allocations.push(MarketAllocation(idleParams, INITIAL_DEPOSIT));
        publicAllocator.reallocate(allocations);
    }

    function testReallocateReset(uint128 flow) public {
        flow = uint128(bound(flow, 0, CAP2 / 2));
        vm.assume(flow != 0);

        vm.prank(OWNER);
        publicAllocator.setFlow(FlowConfig(idleParams.id(),FlowCaps(flow,0),false));
        vm.prank(OWNER);
        publicAllocator.setFlow(FlowConfig(allMarkets[0].id(), FlowCaps(0, flow), false));

        allocations.push(MarketAllocation(idleParams, INITIAL_DEPOSIT - flow));
        allocations.push(MarketAllocation(allMarkets[0], flow));
        publicAllocator.reallocate(allocations);

        vm.prank(OWNER);
        publicAllocator.setFlow(FlowConfig(idleParams.id(),FlowCaps(flow,0),true));
        vm.prank(OWNER);
        publicAllocator.setFlow(FlowConfig(allMarkets[0].id(), FlowCaps(0, flow), true));

        delete allocations;

        allocations.push(MarketAllocation(idleParams, INITIAL_DEPOSIT - flow * 2));
        allocations.push(MarketAllocation(allMarkets[0], flow * 2));
        publicAllocator.reallocate(allocations);
    }

    function testFeeAmountSuccess(uint256 requiredFee, uint256 givenFee) public {
        vm.prank(OWNER);
        publicAllocator.setFee(requiredFee);

        givenFee = bound(givenFee, requiredFee, type(uint256).max);
        vm.deal(address(this), givenFee);

        publicAllocator.reallocate{value: givenFee}(allocations);
    }

    function testFeeAmountFail(uint256 requiredFee, uint256 givenFee) public {
        vm.assume(requiredFee > 0);

        vm.prank(OWNER);
        publicAllocator.setFee(requiredFee);

        givenFee = bound(givenFee, 0, requiredFee - 1);
        vm.deal(address(this), givenFee);
        vm.expectRevert(PAErrorsLib.FeeTooLow.selector);

        publicAllocator.reallocate{value: givenFee}(allocations);
    }

    function testTransferFeeSuccess() public {
        vm.prank(OWNER);
        publicAllocator.setFee(0.001 ether);

        publicAllocator.reallocate{value: 0.01 ether}(allocations);
        publicAllocator.reallocate{value: 0.005 ether}(allocations);

        uint256 before = address(this).balance;

        vm.prank(OWNER);
        publicAllocator.transferFee(address(this));

        assertEq(address(this).balance - before, 0.01 ether + 0.005 ether, "wrong fee transferred");
    }

    function testTransferFeeFail() public {
        vm.prank(OWNER);
        publicAllocator.setFee(0.001 ether);

        publicAllocator.reallocate{value: 0.01 ether}(allocations);

        CantReceive cr = new CantReceive();
        vm.expectRevert(PAErrorsLib.FeeTransferFail.selector);
        vm.prank(OWNER);
        publicAllocator.transferFee(address(cr));
    }

    function testTransferOKOnZerobalance() public {
        vm.prank(OWNER);
        publicAllocator.setFee(0.001 ether);

        CantReceive cr = new CantReceive();
        vm.prank(OWNER);
        publicAllocator.transferFee(address(cr));
    }

    receive() external payable {}
}
