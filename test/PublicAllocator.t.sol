// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../lib/metamorpho/test/forge/helpers/IntegrationTest.sol";
import {PublicAllocator, FlowConfig, SupplyConfig, FlowCap} from "../src/PublicAllocator.sol";
import {ErrorsLib as PAErrorsLib} from "../src/libraries/ErrorsLib.sol";
import {UtilsLib} from "../lib/metamorpho/lib/morpho-blue/src/libraries/UtilsLib.sol";
import {IPublicAllocator} from "../src/interfaces/IPublicAllocator.sol";
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
    MarketAllocation[] internal allocations;
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
        assertEq(publicAllocator.owner(), address(OWNER));
    }

    function testReallocateCapZeroOutflowByDefault(uint256 flow) public {
        flow = uint128(bound(flow, 1, CAP2));
        allocations.push(MarketAllocation(idleParams, INITIAL_DEPOSIT - flow));
        allocations.push(MarketAllocation(allMarkets[0], flow));
        vm.expectRevert(stdError.arithmeticError);
        publicAllocator.reallocate(allocations);
    }

    function testReallocateCapZeroInflowByDefault(uint128 flow) public {
        flow = uint128(bound(flow, 1, CAP2));
        deal(address(loanToken), address(vault), flow);
        allocations.push(MarketAllocation(allMarkets[0], flow));
        allocations.push(MarketAllocation(idleParams, INITIAL_DEPOSIT - flow));
        vm.expectRevert(stdError.arithmeticError);
        publicAllocator.reallocate(allocations);
    }

    function testConfigureFlowAccess(address sender) public {
        vm.assume(sender != OWNER);

        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(0, 0)));

        vm.prank(sender);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, sender));
        publicAllocator.setFlowCaps(flowCaps);
    }

    function testTransferFeeAccess(address sender, address payable recipient) public {
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

    function testSetCapAccess(address sender, Id id, uint256 cap) public {
        vm.assume(sender != OWNER);
        vm.prank(sender);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, sender));
        supplyCaps.push(SupplyConfig(id,cap));
        publicAllocator.setSupplyCaps(supplyCaps);
    }

    function testSetFee(uint fee) public {
        vm.prank(OWNER);
        vm.expectEmit(address(publicAllocator));
        emit EventsLib.SetFee(fee);
        publicAllocator.setFee(fee);
        assertEq(publicAllocator.fee(),fee);
    }

    function testSetFlowCaps(uint128 in0, uint128 out0, uint128 in1, uint128 out1) public {
        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(in0, out0)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(in1, out1)));

        vm.expectEmit(address(publicAllocator));
        emit EventsLib.SetFlowCaps(flowCaps);

        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        FlowCap memory flowCap;
        flowCap = publicAllocator.flowCap(idleParams.id());
        assertEq(flowCap.maxIn,in0);
        assertEq(flowCap.maxOut,out0);

        flowCap = publicAllocator.flowCap(allMarkets[0].id());
        assertEq(flowCap.maxIn,in1);
        assertEq(flowCap.maxOut,out1);
    }

    function testSetSupplyCaps(uint cap0, uint cap1) public {
        supplyCaps.push(SupplyConfig(idleParams.id(), cap0));
        supplyCaps.push(SupplyConfig(allMarkets[0].id(), cap1));

        vm.expectEmit(address(publicAllocator));
        emit EventsLib.SetSupplyCaps(supplyCaps);

        vm.prank(OWNER);
        publicAllocator.setSupplyCaps(supplyCaps);

        uint cap;
        cap = publicAllocator.supplyCap(idleParams.id());
        assertEq(cap, cap0);

        cap = publicAllocator.supplyCap(allMarkets[0].id());
        assertEq(cap, cap1);
    }

    function testPublicReallocateEvent(uint128 flow, uint128 fee, address sender) public {
        vm.deal(sender,fee);
        flow = uint128(bound(flow, 1, CAP2));

        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(0, flow)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(flow, 0)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        allocations.push(MarketAllocation(idleParams, INITIAL_DEPOSIT - flow));
        allocations.push(MarketAllocation(allMarkets[0], flow));

        vm.expectEmit(address(publicAllocator));
        emit EventsLib.PublicReallocate(sender,fee);

        vm.prank(sender);
        publicAllocator.reallocate{value:fee}(allocations);
    }

    function testReallocateNetting(uint128 flow) public {
        flow = uint128(bound(flow, 1, CAP2));

        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(0, flow)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(flow, 0)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        allocations.push(MarketAllocation(idleParams, INITIAL_DEPOSIT - flow));
        allocations.push(MarketAllocation(allMarkets[0], flow));
        publicAllocator.reallocate(allocations);

        delete allocations;
        allocations.push(MarketAllocation(allMarkets[0], 0));
        allocations.push(MarketAllocation(idleParams, INITIAL_DEPOSIT));
        publicAllocator.reallocate(allocations);
    }

    function testReallocateReset(uint128 flow) public {
        flow = uint128(bound(flow, 1, CAP2 / 2));

        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(0, flow)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(flow, 0)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        allocations.push(MarketAllocation(idleParams, INITIAL_DEPOSIT - flow));
        allocations.push(MarketAllocation(allMarkets[0], flow));
        publicAllocator.reallocate(allocations);

        delete flowCaps;
        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(0, flow)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(flow, 0)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

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
        publicAllocator.transferFee(payable(address(this)));

        assertEq(address(this).balance - before, 0.01 ether + 0.005 ether, "wrong fee transferred");
    }

    function testTransferFeeFail() public {
        vm.prank(OWNER);
        publicAllocator.setFee(0.001 ether);

        publicAllocator.reallocate{value: 0.01 ether}(allocations);

        CantReceive cr = new CantReceive();
        vm.expectRevert("cannot receive");
        vm.prank(OWNER);
        publicAllocator.transferFee(payable(address(cr)));
    }

    function testTransferOKOnZerobalance() public {
        vm.prank(OWNER);
        publicAllocator.setFee(0.001 ether);

        CantReceive cr = new CantReceive();
        vm.prank(OWNER);
        publicAllocator.transferFee(payable(address(cr)));
    }

    receive() external payable {}

    function testInflowGoesAboveCap(uint256 cap, uint128 flow) public {
        cap = bound(cap, 0, CAP2 - 1);
        flow = uint128(bound(flow, cap + 1, CAP2));

        supplyCaps.push(SupplyConfig(allMarkets[0].id(), cap));
        vm.prank(OWNER);
        publicAllocator.setSupplyCaps(supplyCaps);

        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(0, type(uint128).max)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(type(uint128).max, 0)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        // Should work at cap
        allocations.push(MarketAllocation(idleParams, INITIAL_DEPOSIT - cap));
        allocations.push(MarketAllocation(allMarkets[0], cap));
        publicAllocator.reallocate(allocations);

        delete allocations;

        // Should not work above cap
        allocations.push(MarketAllocation(idleParams, INITIAL_DEPOSIT - flow));
        allocations.push(MarketAllocation(allMarkets[0], flow));

        vm.expectRevert(
            abi.encodeWithSelector(PAErrorsLib.PublicAllocatorSupplyCapExceeded.selector, allMarkets[0].id())
        );
        publicAllocator.reallocate(allocations);
    }

    function testInflowStartsAboveCap(uint256 cap, uint128 flow) public {
        cap = bound(cap, 0, CAP2 - 2);
        flow = uint128(bound(flow, cap, CAP2 - 1));

        // Remove flow limits
        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(0, type(uint128).max)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(type(uint128).max, 0)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        // Set supply above future public allocator cap
        allocations.push(MarketAllocation(idleParams, INITIAL_DEPOSIT - flow));
        allocations.push(MarketAllocation(allMarkets[0], flow));
        publicAllocator.reallocate(allocations);

        // Set supply in market 0 > public allocation cap
        supplyCaps.push(SupplyConfig(allMarkets[0].id(), cap));
        vm.prank(OWNER);
        publicAllocator.setSupplyCaps(supplyCaps);

        // Increase supply even more (by 1)
        allocations[0].assets = INITIAL_DEPOSIT - flow - 1;
        allocations[1].assets = flow + 1;

        vm.expectRevert(
            abi.encodeWithSelector(PAErrorsLib.PublicAllocatorSupplyCapExceeded.selector, allMarkets[0].id())
        );
        publicAllocator.reallocate(allocations);
    }

    function testStrictOutflowStartsAboveCap(uint256 cap, uint128 flow, uint128 flow2) public {
        cap = bound(cap, 0, CAP2 - 2);
        flow = uint128(bound(flow, cap + 2, CAP2));
        flow2 = uint128(bound(flow2, cap + 1, flow - 1));

        // Remove flow limits
        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(0, type(uint128).max)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(type(uint128).max, 0)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        // Set supply above future public allocator cap
        allocations.push(MarketAllocation(idleParams, INITIAL_DEPOSIT - flow));
        allocations.push(MarketAllocation(allMarkets[0], flow));
        publicAllocator.reallocate(allocations);

        // Set supply in market 0 > public allocation cap
        supplyCaps.push(SupplyConfig(allMarkets[0].id(), cap));
        vm.prank(OWNER);
        publicAllocator.setSupplyCaps(supplyCaps);

        // Strictly decrease supply
        delete allocations;
        allocations.push(MarketAllocation(allMarkets[0], flow2));
        allocations.push(MarketAllocation(idleParams, INITIAL_DEPOSIT - flow2));

        publicAllocator.reallocate(allocations);
    }

    function testMaxOutNoOverflow(uint128 flow) public {
        flow = uint128(bound(flow, 1, CAP2));

        // Set flow limits with supply market's maxOut to max
        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(0, type(uint128).max)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(type(uint128).max, type(uint128).max)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        allocations.push(MarketAllocation(idleParams, INITIAL_DEPOSIT - flow));
        allocations.push(MarketAllocation(allMarkets[0], flow));
        publicAllocator.reallocate(allocations);
    }

    function testMaxInNoOverflow(uint128 flow) public {
        flow = uint128(bound(flow, 1, CAP2));

        // Set flow limits with withdraw market's maxIn to max
        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(type(uint128).max, type(uint128).max)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(type(uint128).max, 0)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        allocations.push(MarketAllocation(idleParams, INITIAL_DEPOSIT - flow));
        allocations.push(MarketAllocation(allMarkets[0], flow));
        publicAllocator.reallocate(allocations);
    }

    function testReallocationReallocates(uint128 flow) public {
        flow = uint128(bound(flow, 0, CAP2));

        // Set flow limits
        flowCaps.push(FlowConfig(idleParams.id(), FlowCap(type(uint128).max, type(uint128).max)));
        flowCaps.push(FlowConfig(allMarkets[0].id(), FlowCap(type(uint128).max, 0)));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(flowCaps);

        uint256 idleBefore = morpho.expectedSupplyAssets(idleParams, address(vault));
        uint256 marketBefore = morpho.expectedSupplyAssets(allMarkets[0], address(vault));
        allocations.push(MarketAllocation(idleParams, INITIAL_DEPOSIT - flow));
        allocations.push(MarketAllocation(allMarkets[0], flow));
        publicAllocator.reallocate(allocations);
        uint256 idleAfter = morpho.expectedSupplyAssets(idleParams, address(vault));
        uint256 marketAfter = morpho.expectedSupplyAssets(allMarkets[0], address(vault));

        assertEq(idleBefore - idleAfter, flow);
        assertEq(marketAfter - marketBefore, flow);
    }
}
