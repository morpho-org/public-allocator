// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../lib/metamorpho/test/forge/helpers/IntegrationTest.sol";
import {PublicAllocator, FlowConfig, Withdrawal, FlowCaps} from "../src/PublicAllocator.sol";
import {ErrorsLib as PAErrorsLib} from "../src/libraries/ErrorsLib.sol";
import {UtilsLib} from "../lib/metamorpho/lib/morpho-blue/src/libraries/UtilsLib.sol";
import {IPublicAllocator} from "../src/interfaces/IPublicAllocator.sol";

uint256 constant CAP2 = 100e18;
uint256 constant INITIAL_DEPOSIT = 4 * CAP2;

contract CantReceive {}

contract PublicAllocatorTest is IntegrationTest {
    IPublicAllocator public publicAllocator;
    Withdrawal[] internal withdrawals;

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
        _sortSupplyQueueIdleLast();

        // Remove public allocator caps by default
        vm.prank(OWNER);
        publicAllocator.setCap(idleParams.id(), type(uint256).max);
        vm.prank(OWNER);
        publicAllocator.setCap(allMarkets[0].id(), type(uint256).max);
    }

    function testOwner() public {
        assertEq(publicAllocator.owner(), address(OWNER));
    }

    function testReallocateCapZeroOutflowByDefault(uint128 flow) public {
        flow = uint128(bound(flow, 0, CAP2));
        vm.assume(flow != 0);
        vm.prank(OWNER);
        publicAllocator.setFlow(FlowConfig(allMarkets[0].id(), FlowCaps(type(uint128).max,0)));
        withdrawals.push(Withdrawal(idleParams,flow));
        vm.expectRevert(stdError.arithmeticError);
        publicAllocator.withdrawTo(withdrawals,allMarkets[0]);
    }

    function testReallocateCapZeroInflowByDefault(uint128 flow) public {
        flow = uint128(bound(flow, 0, CAP2));
        vm.assume(flow != 0);
        deal(address(loanToken), address(vault), flow);
        vm.prank(OWNER);
        publicAllocator.setFlow(FlowConfig(idleParams.id(), FlowCaps(0, type(uint128).max)));
        withdrawals.push(Withdrawal(idleParams,flow));
        vm.expectRevert(stdError.arithmeticError);
        publicAllocator.withdrawTo(withdrawals,allMarkets[0]);
    }

    function testConfigureFlowAccess(address sender) public {
        vm.assume(sender != OWNER);
        vm.prank(sender);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, sender));
        publicAllocator.setFlow(FlowConfig(idleParams.id(), FlowCaps(0, 0)));
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

    function testSetCapAccess(address sender, Id id, uint256 cap) public {
        vm.assume(sender != OWNER);
        vm.prank(sender);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, sender));
        publicAllocator.setCap(id, cap);
    }

    function testReallocateNetting(uint128 flow) public {
        flow = uint128(bound(flow, 0, CAP2));
        vm.assume(flow != 0);

        vm.prank(OWNER);
        publicAllocator.setFlow(FlowConfig(idleParams.id(), FlowCaps(0, flow)));
        vm.prank(OWNER);
        publicAllocator.setFlow(FlowConfig(allMarkets[0].id(), FlowCaps(flow, 0)));

        withdrawals.push(Withdrawal(idleParams, flow));
        publicAllocator.withdrawTo(withdrawals,allMarkets[0]);

        delete withdrawals;
        withdrawals.push(Withdrawal(allMarkets[0], flow));
        publicAllocator.withdrawTo(withdrawals,idleParams);
    }

    function testReallocateReset(uint128 flow) public {
        flow = uint128(bound(flow, 0, CAP2 / 2));
        vm.assume(flow != 0);

        vm.prank(OWNER);
        publicAllocator.setFlow(FlowConfig(idleParams.id(), FlowCaps(0, flow)));
        vm.prank(OWNER);
        publicAllocator.setFlow(FlowConfig(allMarkets[0].id(), FlowCaps(flow, 0)));

        withdrawals.push(Withdrawal(idleParams, flow));
        publicAllocator.withdrawTo(withdrawals,allMarkets[0]);

        vm.prank(OWNER);
        publicAllocator.setFlow(FlowConfig(idleParams.id(), FlowCaps(0, flow)));
        vm.prank(OWNER);
        publicAllocator.setFlow(FlowConfig(allMarkets[0].id(), FlowCaps(flow, 0)));

        delete withdrawals;

        withdrawals.push(Withdrawal(idleParams, flow));
        publicAllocator.withdrawTo(withdrawals, allMarkets[0]);
    }

    function testFeeAmountSuccess(uint256 requiredFee, uint256 givenFee) public {
        vm.prank(OWNER);
        publicAllocator.setFee(requiredFee);

        givenFee = bound(givenFee, requiredFee, type(uint256).max);
        vm.deal(address(this), givenFee);

        publicAllocator.withdrawTo{value: givenFee}(withdrawals,allMarkets[0]);
    }

    function testFeeAmountFail(uint256 requiredFee, uint256 givenFee) public {
        vm.assume(requiredFee > 0);

        vm.prank(OWNER);
        publicAllocator.setFee(requiredFee);

        givenFee = bound(givenFee, 0, requiredFee - 1);
        vm.deal(address(this), givenFee);
        vm.expectRevert(PAErrorsLib.FeeTooLow.selector);

        publicAllocator.withdrawTo{value: givenFee}(withdrawals,allMarkets[0]);
    }

    function testTransferFeeSuccess() public {
        vm.prank(OWNER);
        publicAllocator.setFee(0.001 ether);

        publicAllocator.withdrawTo{value: 0.01 ether}(withdrawals,allMarkets[0]);
        publicAllocator.withdrawTo{value: 0.005 ether}(withdrawals,allMarkets[0]);

        uint256 before = address(this).balance;

        vm.prank(OWNER);
        publicAllocator.transferFee(address(this));

        assertEq(address(this).balance - before, 0.01 ether + 0.005 ether, "wrong fee transferred");
    }

    function testTransferFeeFail() public {
        vm.prank(OWNER);
        publicAllocator.setFee(0.001 ether);

        publicAllocator.withdrawTo{value: 0.01 ether}(withdrawals,allMarkets[0]);

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

    function testInflowGoesAboveCap(uint256 cap, uint128 flow) public {
        cap = bound(cap, 0, CAP2 - 1);
        flow = uint128(bound(flow, cap + 1, CAP2));

        vm.startPrank(OWNER);
        publicAllocator.setCap(allMarkets[0].id(), cap);
        publicAllocator.setFlow(FlowConfig(idleParams.id(), FlowCaps(0, type(uint128).max)));
        publicAllocator.setFlow(FlowConfig(allMarkets[0].id(), FlowCaps(type(uint128).max, 0)));
        vm.stopPrank();

        // Should work at cap
        withdrawals.push(Withdrawal(idleParams, uint128(cap)));
        publicAllocator.withdrawTo(withdrawals,allMarkets[0]);

        delete withdrawals;

        // Should not work above cap
        withdrawals.push(Withdrawal(idleParams, uint128(flow-cap)));

        vm.expectRevert(
            abi.encodeWithSelector(PAErrorsLib.PublicAllocatorSupplyCapExceeded.selector, allMarkets[0].id())
        );
        publicAllocator.withdrawTo(withdrawals, allMarkets[0]);
    }

    function testInflowStartsAboveCap(uint256 cap, uint128 flow) public {
        cap = bound(cap, 0, CAP2 - 2);
        flow = uint128(bound(flow, cap, CAP2 - 1));

        // Remove flow limits
        vm.prank(OWNER);
        publicAllocator.setFlow(FlowConfig(idleParams.id(), FlowCaps(0, type(uint128).max)));
        vm.prank(OWNER);
        publicAllocator.setFlow(FlowConfig(allMarkets[0].id(), FlowCaps(type(uint128).max, 0)));

        // Set supply above future public allocator cap
        withdrawals.push(Withdrawal(idleParams, flow));
        publicAllocator.withdrawTo(withdrawals,allMarkets[0]);

        // Set supply in market 0 > public allocation cap
        vm.prank(OWNER);
        publicAllocator.setCap(allMarkets[0].id(), cap);

        // Increase supply even more (by 1)
        withdrawals[0].amount = 1;

        vm.expectRevert(
            abi.encodeWithSelector(PAErrorsLib.PublicAllocatorSupplyCapExceeded.selector, allMarkets[0].id())
        );
        publicAllocator.withdrawTo(withdrawals,allMarkets[0]);
    }

    function testStrictOutflowStartsAboveCap(uint256 cap, uint128 flow, uint128 flow2) public {
        cap = bound(cap, 0, CAP2 - 2);
        flow = uint128(bound(flow, cap + 2, CAP2));
        flow2 = uint128(bound(flow2, cap + 1, flow - 1));

        // Remove flow limits
        vm.prank(OWNER);
        publicAllocator.setFlow(FlowConfig(idleParams.id(), FlowCaps(0, type(uint128).max)));
        vm.prank(OWNER);
        publicAllocator.setFlow(FlowConfig(allMarkets[0].id(), FlowCaps(type(uint128).max, 0)));

        // Set supply above future public allocator cap
        withdrawals.push(Withdrawal(idleParams, flow));
        publicAllocator.withdrawTo(withdrawals, allMarkets[0]);

        // Set supply in market 0 > public allocation cap
        vm.prank(OWNER);
        publicAllocator.setCap(allMarkets[0].id(), cap);

        // Strictly decrease supply
        delete withdrawals;

        withdrawals.push(Withdrawal(allMarkets[0], flow-flow2));

        publicAllocator.withdrawTo(withdrawals,idleParams);
    }
}
