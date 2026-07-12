// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {FundMe} from "../src/FundMe.sol";
import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

contract FundMeTest is Test {
    FundMe fundMe;
    MockV3Aggregator mockPriceFeed;

    address OWNER = address(this);
    address ALICE = makeAddr("alice");
    address BOB = makeAddr("bob");

    uint256 constant STARTING_BALANCE = 10 ether;
    uint256 constant SEND_VALUE = 1 ether; // well above $1 min at mock price
    int256 constant INITIAL_PRICE = 2000e8; // $2000 with 8 decimals, like Chainlink

    event Funded(address indexed funder, uint256 amount);
    event Withdrawn(address indexed owner, uint256 amount);

    function setUp() public {
        mockPriceFeed = new MockV3Aggregator(8, INITIAL_PRICE);
        fundMe = new FundMe(AggregatorV3Interface(address(mockPriceFeed)));

        vm.deal(ALICE, STARTING_BALANCE);
        vm.deal(BOB, STARTING_BALANCE);
    }

    /* ---------------------------------- *
     *           CONSTRUCTOR              *
     * ---------------------------------- */

    function test_OwnerIsDeployer() public view {
        assertEq(fundMe.getOwner(), OWNER);
    }

    function test_PriceFeedSetCorrectly() public view {
        assertEq(address(fundMe.getPriceFeed()), address(mockPriceFeed));
    }

    function test_MinimumUsdIsOneDollar() public view {
        assertEq(fundMe.getMinimumUsd(), 1e18);
    }

    /* ---------------------------------- *
     *               FUND                 *
     * ---------------------------------- */

    function test_FundRevertsIfBelowMinimumUsd() public {
        vm.prank(ALICE);
        vm.expectRevert(bytes("Need more ETH"));
        fundMe.fund{value: 1}(); // 1 wei, way below $1
    }

    function test_FundUpdatesAmountFunded() public {
        vm.prank(ALICE);
        fundMe.fund{value: SEND_VALUE}();

        assertEq(fundMe.getAmountFunded(ALICE), SEND_VALUE);
    }

    function test_FundAddsFunderToArray() public {
        vm.prank(ALICE);
        fundMe.fund{value: SEND_VALUE}();

        assertEq(fundMe.getFunder(0), ALICE);
        assertEq(fundMe.getFundersLength(), 1);
    }

    function test_FundUpdatesTotalDeposit() public {
        vm.prank(ALICE);
        fundMe.fund{value: SEND_VALUE}();

        assertEq(fundMe.getTotalDeposit(), SEND_VALUE);
    }

    function test_FundEmitsFundedEvent() public {
        vm.expectEmit(true, false, false, true);
        emit Funded(ALICE, SEND_VALUE);

        vm.prank(ALICE);
        fundMe.fund{value: SEND_VALUE}();
    }

    function test_MultipleFundersTracked() public {
        vm.prank(ALICE);
        fundMe.fund{value: SEND_VALUE}();

        vm.prank(BOB);
        fundMe.fund{value: SEND_VALUE}();

        assertEq(fundMe.getFundersLength(), 2);
        assertEq(fundMe.getFunder(0), ALICE);
        assertEq(fundMe.getFunder(1), BOB);
        assertEq(fundMe.getTotalDeposit(), SEND_VALUE * 2);
    }

    function test_SameFunderFundingTwiceAccumulates() public {
        vm.startPrank(ALICE);
        fundMe.fund{value: SEND_VALUE}();
        fundMe.fund{value: SEND_VALUE}();
        vm.stopPrank();

        assertEq(fundMe.getAmountFunded(ALICE), SEND_VALUE * 2);
        // pushed twice even though same address - matches current contract logic
        assertEq(fundMe.getFundersLength(), 2);
    }

    function testFuzz_FundRevertsBelowMinimum(uint96 amount) public {
        // bound to values guaranteed to be below $1 at $2000/ETH
        vm.assume(amount < 5e14); // 0.0005 ETH ~ $1 at $2000/ETH, stay safely under
        vm.deal(ALICE, amount);

        vm.prank(ALICE);
        vm.expectRevert(bytes("Need more ETH"));
        fundMe.fund{value: amount}();
    }

    /* ---------------------------------- *
     *           RECEIVE / FALLBACK       *
     * ---------------------------------- */

    function test_ReceiveCallsFund() public {
        vm.prank(ALICE);
        (bool success,) = address(fundMe).call{value: SEND_VALUE}("");

        assertTrue(success);
        assertEq(fundMe.getAmountFunded(ALICE), SEND_VALUE);
    }

    function test_FallbackCallsFund() public {
        vm.prank(ALICE);
        (bool success,) = address(fundMe).call{value: SEND_VALUE}(abi.encodeWithSignature("nonExistentFn()"));

        assertTrue(success);
        assertEq(fundMe.getAmountFunded(ALICE), SEND_VALUE);
    }

    /* ---------------------------------- *
     *              WITHDRAW              *
     * ---------------------------------- */

    modifier funded() {
        vm.prank(ALICE);
        fundMe.fund{value: SEND_VALUE}();
        vm.prank(BOB);
        fundMe.fund{value: SEND_VALUE}();
        _;
    }

    function test_WithdrawRevertsIfNotOwner() public funded {
        vm.prank(ALICE);
        vm.expectRevert(FundMe.FundMe_NotOwner.selector);
        fundMe.withdraw();
    }

    function test_OwnerCanWithdraw() public funded {
        uint256 startingOwnerBalance = OWNER.balance;
        uint256 startingFundMeBalance = address(fundMe).balance;

        fundMe.withdraw();

        assertEq(address(fundMe).balance, 0);
        assertEq(OWNER.balance, startingOwnerBalance + startingFundMeBalance);
    }

    function test_WithdrawResetsFundersArray() public funded {
        fundMe.withdraw();
        assertEq(fundMe.getFundersLength(), 0);
    }

    function test_WithdrawResetsAmountFundedPerFunder() public funded {
        fundMe.withdraw();
        assertEq(fundMe.getAmountFunded(ALICE), 0);
        assertEq(fundMe.getAmountFunded(BOB), 0);
    }

    function test_WithdrawResetsTotalDeposit() public funded {
        fundMe.withdraw();
        assertEq(fundMe.getTotalDeposit(), 0);
    }

    function test_WithdrawEmitsWithdrawnEventWithCorrectAmount() public funded {
        uint256 expectedAmount = address(fundMe).balance;

        vm.expectEmit(true, false, false, true);
        emit Withdrawn(OWNER, expectedAmount);

        fundMe.withdraw();
    }

    function test_WithdrawWithSingleFunder() public {
        vm.prank(ALICE);
        fundMe.fund{value: SEND_VALUE}();

        uint256 startingOwnerBalance = OWNER.balance;

        fundMe.withdraw();

        assertEq(address(fundMe).balance, 0);
        assertEq(OWNER.balance, startingOwnerBalance + SEND_VALUE);
    }

    function test_WithdrawWithNoFundersDoesNotRevert() public {
        fundMe.withdraw();
        assertEq(address(fundMe).balance, 0);
    }

    /* ---------------------------------- *
     *           PRICE / VERSION          *
     * ---------------------------------- */

    function test_GetEthPriceMatchesMockFeed() public view {
        // INITIAL_PRICE has 8 decimals, getPrice scales to 18 decimals
        uint256 expected = uint256(INITIAL_PRICE) * 1e10;
        assertEq(fundMe.getEthPrice(), expected);
    }

    function test_GetEthPriceUpdatesWhenFeedUpdates() public {
        int256 newPrice = 3000e8;
        mockPriceFeed.updateAnswer(newPrice);

        uint256 expected = uint256(newPrice) * 1e10;
        assertEq(fundMe.getEthPrice(), expected);
    }

    function test_GetVersionMatchesMock() public view {
        assertEq(fundMe.getVersion(), 4);
    }

    function test_GetConversionRate() public view {
        uint256 oneEthInUsd = fundMe.getConversionRate(1 ether);
        // at $2000/ETH, 1 ETH = $2000 = 2000e18
        assertEq(oneEthInUsd, 2000e18);
    }

    /* ---------------------------------- *
     *              GETTERS               *
     * ---------------------------------- */

    function test_GetBalanceMatchesContractBalance() public funded {
        assertEq(fundMe.getBalance(), address(fundMe).balance);
    }

    receive() external payable {}
}
