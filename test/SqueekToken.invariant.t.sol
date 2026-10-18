// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SqueekToken} from "../src/SqueekToken.sol";

/// @dev Maintains an independent ledger across successful and rejected operations.
contract SqueekHandler is Test {
    SqueekToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(SqueekToken token_) {
        token = token_;
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("invariant actor ", vm.toString(i)));
        }
        expectedBalance[actors[0]] = 1_000_000_000 ether;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed, bool overspend) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 held = expectedBalance[from];
        uint256 amount = overspend ? held + 1 : bound(amountSeed, 0, held);

        if (overspend) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount));
            vm.prank(from);
            token.transfer(to, amount);
            return;
        }

        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool unlimited) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = unlimited ? type(uint256).max : bound(amountSeed, 0, 1_000_000_000 ether);

        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed, bool overspend)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 held = expectedBalance[owner];
        uint256 approved = expectedAllowance[owner][spender];
        uint256 available = held < approved ? held : approved;
        uint256 amount = overspend ? available + 1 : bound(amountSeed, 0, available);

        if (overspend) {
            if (amount > approved) {
                vm.expectRevert(
                    abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
                );
            } else {
                vm.expectRevert(
                    abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount)
                );
            }
            vm.prank(spender);
            token.transferFrom(owner, to, amount);
            return;
        }

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (approved != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
    }
}

contract SqueekTokenInvariantTest is Test {
    SqueekToken internal token;
    SqueekHandler internal handler;

    function setUp() public {
        token = new SqueekToken();
        handler = new SqueekHandler(token);
        token.transfer(handler.actors(0), 1_000_000_000 ether);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyAndBalancesMatchIndependentLedger() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            sum += balance;
        }
        assertEq(sum, 1_000_000_000 ether);
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_allowancesMatchIndependentLedger() public view {
        for (uint256 i; i < 4; ++i) {
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }
}
