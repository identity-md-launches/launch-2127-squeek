// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SqueekToken} from "../src/SqueekToken.sol";

/// @dev Complements the deployment/basic ERC-20 tests with authorization,
/// failure recovery, and algebraic properties across multiple transactions.
/// forge-config: default.fuzz.runs = 1024
contract SqueekTokenAdversarialTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    SqueekToken internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new SqueekToken();
        alice = makeAddr("adversarial alice");
        bob = makeAddr("adversarial bob");
        spender = makeAddr("adversarial spender");
    }

    function test_oneWeiCanMoveAndReturnThroughAllowance() public {
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, address(this), 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, address(this), 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maxMinusOneAllowanceIsFinite() public {
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_ownerNeedsSelfApprovalForTransferFrom() public {
        token.transfer(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);

        vm.startPrank(alice);
        assertTrue(token.approve(alice, 1));
        assertTrue(token.transferFrom(alice, bob, 1));
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.allowance(alice, alice), 0);
    }

    function test_approvalCannotBeBorrowedFromAnotherSpender() public {
        token.approve(spender, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(address(this), spender), SUPPLY);
        assertEq(token.allowance(address(this), bob), 0);
    }

    function test_revokingOneSpenderPreservesTheOther() public {
        token.approve(spender, type(uint256).max);
        token.approve(bob, 2);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), bob), 2);
        vm.prank(bob);
        assertTrue(token.transferFrom(address(this), alice, 2));
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.allowance(address(this), bob), 0);
    }

    function test_unlimitedApprovalCanBeReplacedWithFiniteAllowance() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertTrue(token.approve(spender, 1));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 1, 2));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 2);
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.balanceOf(alice), 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
    }

    function test_returningTokensDoesNotRestoreSpentAllowance() public {
        token.approve(spender, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        // Exhausting a spender's allowance must not lock the owner's own tokens.
        assertTrue(token.transfer(bob, SUPPLY));
        assertEq(token.balanceOf(bob), SUPPLY);
    }

    function test_balanceFailureRetainsApprovalForRetryAfterFunding() public {
        token.transfer(alice, 1);
        vm.prank(alice);
        token.approve(spender, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(spender);
        token.transferFrom(alice, bob, 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, spender), 2);

        token.transfer(alice, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 2));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 2);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_invalidRecipientRetainsApprovalForRetry() public {
        token.approve(spender, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), spender), SUPPLY);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroAddressIsRejectedEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);

        // Either allowance or sender validation may reject the zero owner first.
        vm.expectRevert();
        vm.prank(spender);
        token.transferFrom(address(0), alice, 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(0), spender), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroDelegatedTransferEmitsEventAndKeepsAllowance() public {
        vm.prank(alice);
        token.approve(spender, 1);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, spender), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_delegatedSelfTransferStillRequiresBalance() public {
        token.transfer(alice, 1);
        vm.prank(alice);
        token.approve(spender, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(spender);
        token.transferFrom(alice, alice, 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.allowance(alice, spender), 2);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_unlimitedAllowanceCannotSpendMaxUintBalance() public {
        token.approve(spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_insufficientAllowanceRevertsAtomically(
        uint256 balanceSeed,
        uint256 approvalSeed,
        uint256 amountSeed
    ) public {
        uint256 held = bound(balanceSeed, 1, SUPPLY - 1);
        uint256 approved = bound(approvalSeed, 0, held - 1);
        uint256 amount = bound(amountSeed, approved + 1, held);
        token.transfer(alice, held);
        token.transfer(bob, 1);
        vm.prank(alice);
        token.approve(spender, approved);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - held - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_insufficientBalanceRestoresFiniteAllowance(
        uint256 balanceSeed,
        uint256 approvalSeed,
        uint256 amountSeed
    ) public {
        uint256 held = bound(balanceSeed, 0, SUPPLY - 1);
        uint256 amount = bound(amountSeed, held + 1, type(uint256).max - 1);
        uint256 approved = bound(approvalSeed, amount, type(uint256).max - 1);
        token.transfer(alice, held);
        token.transfer(bob, 1);
        vm.prank(alice);
        token.approve(spender, approved);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - held - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalReplacementIsIdempotentAndIsolated(uint256 first, uint256 replacement) public {
        token.approve(spender, first);
        token.approve(bob, first);
        vm.prank(alice);
        token.approve(spender, first);

        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        assertEq(token.allowance(address(this), bob), first);
        assertEq(token.allowance(alice, spender), first);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splitSpendingMatchesSingleSpending(uint256 totalSeed, uint256 firstSeed) public {
        uint256 total = bound(totalSeed, 0, SUPPLY);
        uint256 first = bound(firstSeed, 0, total);
        SqueekToken single = new SqueekToken();
        token.approve(spender, total);
        single.approve(spender, total);

        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertEq(token.allowance(address(this), spender), total - first);
        assertEq(token.balanceOf(alice), first);
        assertTrue(token.transferFrom(address(this), alice, total - first));
        assertTrue(single.transferFrom(address(this), alice, total));
        vm.stopPrank();

        assertEq(token.balanceOf(alice), single.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), single.balanceOf(address(this)));
        assertEq(token.balanceOf(alice), total);
        assertEq(token.balanceOf(address(this)), SUPPLY - total);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(single.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(single.totalSupply(), SUPPLY);
    }

    function testFuzz_roundTripPreservesBalancesAndApprovals(uint256 balanceSeed, uint256 amountSeed, uint256 approved)
        public
    {
        uint256 initialAlice = bound(balanceSeed, 0, SUPPLY);
        uint256 initialBob = SUPPLY - initialAlice;
        uint256 amount = bound(amountSeed, 0, initialAlice);
        token.transfer(alice, initialAlice);
        token.transfer(bob, initialBob);
        vm.prank(alice);
        token.approve(spender, approved);

        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(alice), initialAlice - amount);
        assertEq(token.balanceOf(bob), initialBob + amount);
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), initialAlice);
        assertEq(token.balanceOf(bob), initialBob);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_unlimitedApprovalSurvivesRepeatedSpending(uint256 amountSeed, uint256 roundsSeed) public {
        uint256 amount = bound(amountSeed, 1, SUPPLY);
        uint256 rounds = bound(roundsSeed, 2, 8);
        token.approve(spender, type(uint256).max);
        for (uint256 i; i < rounds; ++i) {
            vm.prank(spender);
            assertTrue(token.transferFrom(address(this), alice, amount));
            assertEq(token.balanceOf(alice), amount);
            assertEq(token.balanceOf(address(this)), SUPPLY - amount);
            assertEq(token.allowance(address(this), spender), type(uint256).max);
            vm.prank(alice);
            assertTrue(token.transfer(address(this), amount));
        }
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
