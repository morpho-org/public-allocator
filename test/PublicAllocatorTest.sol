// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {
    IntegrationTest,
    MarketAllocation,
    MarketParamsLib,
    MarketParams,
    IMorpho,
    Id,
    Ownable,
    stdError
} from "../lib/metamorpho/test/forge/helpers/IntegrationTest.sol";
import {PublicAllocator, FlowConfig, SupplyConfig, Withdrawal, FlowCap} from "../src/PublicAllocator.sol";
import {ErrorsLib} from "../src/libraries/ErrorsLib.sol";
import {EventsLib} from "../src/libraries/EventsLib.sol";
import {UtilsLib} from "../lib/metamorpho/lib/morpho-blue/src/libraries/UtilsLib.sol";
import {IPublicAllocator, MAX_SETTABLE_FLOW_CAP} from "../src/interfaces/IPublicAllocator.sol";
import {MorphoBalancesLib} from "../lib/metamorpho/lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";

uint256 constant CAP2 = 100e18;
uint256 constant INITIAL_DEPOSIT = 4 * CAP2;

contract CantReceive {
    receive() external payable {
        require(false, "cannot receive");
    }
}

contract PublicAllocatorTest is IntegrationTest {
    IPublicAllocator public publicAllocator;
    Withdrawal[] internal withdrawals;
    FlowConfig[] internal flowCaps;
    SupplyConfig[] internal supplyCaps;

    using MarketParamsLib for MarketParams;
    using MorphoBalancesLib for IMorpho;

    function setUp() public override {
        super.setUp();

        publicAllocator = IPublicAllocator(address(new PublicAllocator(address(OWNER), address(vault))));
        vm.prank(OWNER);
        vault.setIsAllocator(address(publicAllocator), true);

        loanToken.setBalance(SUPPLIER, INITIAL_DEPOSIT);

        vm.prank(SUPPLIER);
        vault.deposit(INITIAL_DEPOSIT, ONBEHALF);

        _setCap(allMarkets[0], CAP2);
        _sortSupplyQueueIdleLast();

        // Remove public allocator caps by default
        supplyCaps.push(SupplyConfig(idleParams.id(), type(uint256).max));
        supplyCaps.push(SupplyConfig(allMarkets[0].id(), type(uint256).max));
        vm.prank(OWNER);
        publicAllocator.setSupplyCaps(supplyCaps);
        delete supplyCaps;
    }

    function testOwner() public {
        assertEq(publicAllocator.OWNER(), address(OWNER));
    }

    function testDeployAddressZeroFail() public {
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        new PublicAllocator(address(0), address(vault));
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        new PublicAllocator(OWNER, address(0));
    }

    function testReallocateCapZeroOutflowByDefault(uint128 flow) public {
        flow = uint128(bound(flow, 1, CAP2));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(MAX_SETTABLE_FLOW_CAP, 0)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);
        withdrawals.push(Withdrawal(idleParams, flow));
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.MaxOutflowExceeded.selector, idleParams.id()));
        publicAllocator.reallocateTo(withdrawals, allMarkets[0]);
    }

    function testReallocateCapZeroInflowByDefault(uint128 flow) public {
        flow = uint128(bound(flow, 1, CAP2));
        deal(address(loanToken), address(vault), flow);
        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(0, MAX_SETTABLE_FLOW_CAP)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);
        withdrawals.push(Withdrawal(idleParams, flow));
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.MaxInflowExceeded.selector, allMarkets[0].id()));
        publicAllocator.reallocateTo(withdrawals, allMarkets[0]);
    }

    function testConfigureFlowAccessFail(address sender) public {
        vm.assume(sender != OWNER);

        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(0, 0)));

        vm.prank(sender);
        vm.expectRevert(ErrorsLib.NotOwner.selector);
        publicAllocator.setFlowCaps(flowCaps);
    }

    function testTransferFeeAccessFail(address sender, address payable recipient) public {
        vm.assume(sender != OWNER);
        vm.prank(sender);
        vm.expectRevert(ErrorsLib.NotOwner.selector);
        publicAllocator.transferFee(recipient);
    }

    function testSetFeeAccessFail(address sender, uint256 fee) public {
        vm.assume(sender != OWNER);
        vm.prank(sender);
        vm.expectRevert(ErrorsLib.NotOwner.selector);
        publicAllocator.setFee(fee);
    }

    function testSetCapAccessFail(address sender, Id id, uint256 cap) public {
        vm.assume(sender != OWNER);
        vm.prank(sender);
        vm.expectRevert(ErrorsLib.NotOwner.selector);
        supplyCaps.push(SupplyConfig(id, cap));
        publicAllocator.setSupplyCaps(supplyCaps);
    }

    function testSetFee(uint256 fee) public {
        vm.assume(fee != publicAllocator.fee());
        vm.prank(OWNER);
        vm.expectEmit(address(publicAllocator));
        emit EventsLib.SetFee(fee);
        publicAllocator.setFee(fee);
        assertEq(publicAllocator.fee(), fee);
    }

    function testSetFeeAlreadySet(uint256 fee) public {
        vm.assume(fee != publicAllocator.fee());
        vm.prank(OWNER);
        publicAllocator.setFee(fee);
        vm.prank(OWNER);
        vm.expectRevert(ErrorsLib.AlreadySet.selector);
        publicAllocator.setFee(fee);
    }

    function testSetFlowCaps(uint128 in0, uint128 out0, uint128 in1, uint128 out1) public {
        in0 = uint128(bound(in0, 0, MAX_SETTABLE_FLOW_CAP));
        out0 = uint128(bound(out0, 0, MAX_SETTABLE_FLOW_CAP));
        in1 = uint128(bound(in1, 0, MAX_SETTABLE_FLOW_CAP));
        out1 = uint128(bound(out1, 0, MAX_SETTABLE_FLOW_CAP));

        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(in0, out0)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(in1, out1)));

        vm.expectEmit(address(publicAllocator));
        emit EventsLib.SetFlowCaps(flowCaps);

        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        FlowCap memory flowCap;
        flowCap = publicAllocator.flowCap(idleParams.id());
        assertEq(flowCap.maxIn, in0);
        assertEq(flowCap.maxOut, out0);

        flowCap = publicAllocator.flowCap(allMarkets[0].id());
        assertEq(flowCap.maxIn, in1);
        assertEq(flowCap.maxOut, out1);
    }

    function testSetSupplyCaps(uint256 cap0, uint256 cap1) public {
        supplyCaps.push(SupplyConfig(idleParams.id(), cap0));
        supplyCaps.push(SupplyConfig(allMarkets[0].id(), cap1));

        vm.expectEmit(address(publicAllocator));
        emit EventsLib.SetSupplyCaps(supplyCaps);

        vm.prank(OWNER);
        publicAllocator.setSupplyCaps(supplyCaps);

        uint256 cap;
        cap = publicAllocator.supplyCap(idleParams.id());
        assertEq(cap, cap0);

        cap = publicAllocator.supplyCap(allMarkets[0].id());
        assertEq(cap, cap1);
    }

    function testPublicReallocateEvent(uint128 flow, address sender) public {
        flow = uint128(bound(flow, 1, CAP2 / 2));

        // Prepare public reallocation from 2 markets to 1
        _setCap(allMarkets[1], CAP2);

        MarketAllocation[] memory allocations = new MarketAllocation[](2);
        allocations[0] = MarketAllocation(idleParams, INITIAL_DEPOSIT - flow);
        allocations[1] = MarketAllocation(allMarkets[1], flow);
        vm.prank(OWNER);
        vault.reallocate(allocations);

        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(0, flow)));
        flowCaps.push(FlowConfig(allMarkets[1].id(), FlowCap(0, flow)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(2 * flow, 0)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        withdrawals.push(Withdrawal(idleParams, flow));
        withdrawals.push(Withdrawal(allMarkets[1], flow));

        vm.expectEmit(address(publicAllocator));
        emit EventsLib.PublicWithdrawal(idleParams.id(), flow);
        emit EventsLib.PublicWithdrawal(allMarkets[1].id(), flow);
        emit EventsLib.PublicReallocateTo(sender, allMarkets[0].id(), 2 * flow);

        vm.prank(sender);
        publicAllocator.reallocateTo(withdrawals, allMarkets[0]);
    }

    function testReallocateNetting(uint128 flow) public {
        flow = uint128(bound(flow, 1, CAP2));

        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(0, flow)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(flow, 0)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        withdrawals.push(Withdrawal(idleParams, flow));
        publicAllocator.reallocateTo(withdrawals, allMarkets[0]);

        delete withdrawals;
        withdrawals.push(Withdrawal(allMarkets[0], flow));
        publicAllocator.reallocateTo(withdrawals, idleParams);
    }

    function testReallocateReset(uint128 flow) public {
        flow = uint128(bound(flow, 1, CAP2 / 2));

        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(0, flow)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(flow, 0)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        withdrawals.push(Withdrawal(idleParams, flow));
        publicAllocator.reallocateTo(withdrawals, allMarkets[0]);

        delete flowCaps;
        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(0, flow)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(flow, 0)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        delete withdrawals;

        withdrawals.push(Withdrawal(idleParams, flow));
        publicAllocator.reallocateTo(withdrawals, allMarkets[0]);
    }

    function testFeeAmountSuccess(uint256 requiredFee) public {
        vm.assume(requiredFee != publicAllocator.fee());
        vm.prank(OWNER);
        publicAllocator.setFee(requiredFee);

        vm.deal(address(this), requiredFee);

        publicAllocator.reallocateTo{value: requiredFee}(withdrawals, allMarkets[0]);
    }

    function testFeeAmountFail(uint256 requiredFee, uint256 givenFee) public {
        vm.assume(requiredFee > 0);
        vm.assume(requiredFee != givenFee);

        vm.prank(OWNER);
        publicAllocator.setFee(requiredFee);

        vm.deal(address(this), givenFee);
        vm.expectRevert(ErrorsLib.IncorrectFee.selector);

        publicAllocator.reallocateTo{value: givenFee}(withdrawals, allMarkets[0]);
    }

    function testTransferFeeSuccess() public {
        vm.prank(OWNER);
        publicAllocator.setFee(0.001 ether);

        publicAllocator.reallocateTo{value: 0.001 ether}(withdrawals, allMarkets[0]);
        publicAllocator.reallocateTo{value: 0.001 ether}(withdrawals, allMarkets[0]);

        uint256 before = address(this).balance;

        vm.prank(OWNER);
        publicAllocator.transferFee(payable(address(this)));

        assertEq(address(this).balance - before, 2 * 0.001 ether, "wrong fee transferred");
    }

    function testTransferFeeFail() public {
        vm.prank(OWNER);
        publicAllocator.setFee(0.001 ether);

        publicAllocator.reallocateTo{value: 0.001 ether}(withdrawals, allMarkets[0]);

        CantReceive cr = new CantReceive();
        vm.expectRevert("cannot receive");
        vm.prank(OWNER);
        publicAllocator.transferFee(payable(address(cr)));
    }

    function testTransferOKOnZerobalance() public {
        vm.prank(OWNER);
        publicAllocator.transferFee(payable(address(this)));
    }

    receive() external payable {}

    function testInflowGoesAboveCap(uint256 cap, uint128 flow) public {
        cap = bound(cap, 0, CAP2 - 1);
        flow = uint128(bound(flow, cap + 1, CAP2));

        supplyCaps.push(SupplyConfig(allMarkets[0].id(), cap));
        vm.prank(OWNER);
        publicAllocator.setSupplyCaps(supplyCaps);

        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(0, MAX_SETTABLE_FLOW_CAP)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(MAX_SETTABLE_FLOW_CAP, 0)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        // Should work at cap
        withdrawals.push(Withdrawal(idleParams, uint128(cap)));
        publicAllocator.reallocateTo(withdrawals, allMarkets[0]);

        delete withdrawals;

        // Should not work above cap
        withdrawals.push(Withdrawal(idleParams, uint128(flow - cap)));

        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.PublicAllocatorSupplyCapExceeded.selector, allMarkets[0].id()));
        publicAllocator.reallocateTo(withdrawals, allMarkets[0]);
    }

    function testInflowStartsAboveCap(uint256 cap, uint128 flow) public {
        cap = bound(cap, 0, CAP2 - 2);
        flow = uint128(bound(flow, cap, CAP2 - 1));

        // Remove flow limits
        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(0, MAX_SETTABLE_FLOW_CAP)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(MAX_SETTABLE_FLOW_CAP, 0)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        // Set supply above future public allocator cap
        withdrawals.push(Withdrawal(idleParams, flow));
        publicAllocator.reallocateTo(withdrawals, allMarkets[0]);

        // Set supply in market 0 > public allocation cap
        supplyCaps.push(SupplyConfig(allMarkets[0].id(), cap));
        vm.prank(OWNER);
        publicAllocator.setSupplyCaps(supplyCaps);

        // Increase supply even more (by 1)
        withdrawals[0].amount = 1;

        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.PublicAllocatorSupplyCapExceeded.selector, allMarkets[0].id()));
        publicAllocator.reallocateTo(withdrawals, allMarkets[0]);
    }

    function testStrictOutflowStartsAboveCap(uint256 cap, uint128 flow, uint128 flow2) public {
        cap = bound(cap, 0, CAP2 - 2);
        flow = uint128(bound(flow, cap + 2, CAP2));
        flow2 = uint128(bound(flow2, cap + 1, flow - 1));

        // Remove flow limits
        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(0, MAX_SETTABLE_FLOW_CAP)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(MAX_SETTABLE_FLOW_CAP, 0)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        // Set supply above future public allocator cap
        withdrawals.push(Withdrawal(idleParams, flow));
        publicAllocator.reallocateTo(withdrawals, allMarkets[0]);

        // Set supply in market 0 > public allocation cap
        supplyCaps.push(SupplyConfig(allMarkets[0].id(), cap));
        vm.prank(OWNER);
        publicAllocator.setSupplyCaps(supplyCaps);

        // Strictly decrease supply
        delete withdrawals;

        withdrawals.push(Withdrawal(allMarkets[0], flow - flow2));

        publicAllocator.reallocateTo(withdrawals, idleParams);
    }

    function testMaxOutNoOverflow(uint128 flow) public {
        flow = uint128(bound(flow, 1, CAP2));

        // Set flow limits with supply market's maxOut to max
        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(0, MAX_SETTABLE_FLOW_CAP)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(MAX_SETTABLE_FLOW_CAP, MAX_SETTABLE_FLOW_CAP)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        withdrawals.push(Withdrawal(idleParams, flow));
        publicAllocator.reallocateTo(withdrawals, allMarkets[0]);
    }

    function testMaxInNoOverflow(uint128 flow) public {
        flow = uint128(bound(flow, 1, CAP2));

        // Set flow limits with withdraw market's maxIn to max
        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(MAX_SETTABLE_FLOW_CAP, MAX_SETTABLE_FLOW_CAP)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(MAX_SETTABLE_FLOW_CAP, 0)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        withdrawals.push(Withdrawal(idleParams, flow));
        publicAllocator.reallocateTo(withdrawals, allMarkets[0]);
    }

    function testReallocationReallocates(uint128 flow) public {
        flow = uint128(bound(flow, 0, CAP2));

        // Set flow limits
        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(MAX_SETTABLE_FLOW_CAP, MAX_SETTABLE_FLOW_CAP)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(MAX_SETTABLE_FLOW_CAP, 0)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        uint256 idleBefore = morpho.expectedSupplyAssets(idleParams, address(vault));
        uint256 marketBefore = morpho.expectedSupplyAssets(allMarkets[0], address(vault));
        withdrawals.push(Withdrawal(idleParams, flow));
        publicAllocator.reallocateTo(withdrawals, allMarkets[0]);
        uint256 idleAfter = morpho.expectedSupplyAssets(idleParams, address(vault));
        uint256 marketAfter = morpho.expectedSupplyAssets(allMarkets[0], address(vault));

        assertEq(idleBefore - idleAfter, flow);
        assertEq(marketAfter - marketBefore, flow);
    }

    function testDuplicateInWithdrawals() public {
        // Set flow limits
        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(MAX_SETTABLE_FLOW_CAP, MAX_SETTABLE_FLOW_CAP)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(MAX_SETTABLE_FLOW_CAP, 0)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        // Prepare public reallocation from 2 markets to 1
        // _setCap(allMarkets[1], CAP2);
        withdrawals.push(Withdrawal(idleParams, 1e18));
        withdrawals.push(Withdrawal(idleParams, 1e18));
        vm.expectRevert(ErrorsLib.InconsistentWithdrawTo.selector);
        publicAllocator.reallocateTo(withdrawals, allMarkets[0]);
    }

    function testSupplyMarketInWithdrawals() public {
        // Set flow limits
        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(MAX_SETTABLE_FLOW_CAP, MAX_SETTABLE_FLOW_CAP)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(MAX_SETTABLE_FLOW_CAP, 0)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        withdrawals.push(Withdrawal(idleParams, 1e18));
        vm.expectRevert(ErrorsLib.InconsistentWithdrawTo.selector);
        publicAllocator.reallocateTo(withdrawals, idleParams);
    }

    function testMaxFlowCapValue() public {
        assertEq(MAX_SETTABLE_FLOW_CAP, type(uint128).max / 2);
    }

    function testMaxFlowCapLimit(uint128 cap) public {
        cap = uint128(bound(cap, MAX_SETTABLE_FLOW_CAP + 1, type(uint128).max));

        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(0, cap)));

        vm.expectRevert(ErrorsLib.MaxSettableFlowCapExceeded.selector);
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        delete flowCaps;
        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(cap, 0)));

        vm.expectRevert(ErrorsLib.MaxSettableFlowCapExceeded.selector);
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);
    }

    function testNotEnoughSupply() public {
        uint128 flow = 1e18;
        // Set flow limits with withdraw market's maxIn to max
        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(MAX_SETTABLE_FLOW_CAP, MAX_SETTABLE_FLOW_CAP)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(MAX_SETTABLE_FLOW_CAP, MAX_SETTABLE_FLOW_CAP)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        withdrawals.push(Withdrawal(idleParams, flow));
        publicAllocator.reallocateTo(withdrawals, allMarkets[0]);

        delete withdrawals;

        withdrawals.push(Withdrawal(allMarkets[0], flow + 1));
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.NotEnoughSupply.selector, allMarkets[0].id()));
        publicAllocator.reallocateTo(withdrawals, idleParams);
    }

    function testMaxOutflowExceeded() public {
        uint128 cap = 1e18;
        // Set flow limits with withdraw market's maxIn to max
        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(MAX_SETTABLE_FLOW_CAP, cap)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(MAX_SETTABLE_FLOW_CAP, MAX_SETTABLE_FLOW_CAP)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        withdrawals.push(Withdrawal(idleParams, cap + 1));
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.MaxOutflowExceeded.selector, idleParams.id()));
        publicAllocator.reallocateTo(withdrawals, allMarkets[0]);
    }

    function testMaxInflowExceeded() public {
        uint128 cap = 1e18;
        // Set flow limits with withdraw market's maxIn to max
        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(MAX_SETTABLE_FLOW_CAP, MAX_SETTABLE_FLOW_CAP)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(cap, MAX_SETTABLE_FLOW_CAP)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        withdrawals.push(Withdrawal(idleParams, cap + 1));
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.MaxInflowExceeded.selector, allMarkets[0].id()));
        publicAllocator.reallocateTo(withdrawals, allMarkets[0]);
    }
}
