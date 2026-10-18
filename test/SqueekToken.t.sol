// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SqueekToken} from "../src/SqueekToken.sol";
import {TokenFactory, RejectingRecipient} from "./helpers/TokenFactory.sol";

contract SqueekTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    SqueekToken internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new SqueekToken();
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
    }

    function test_metadataAndInitialSupply() public view {
        assertEq(token.name(), "SQUEEK");
        assertEq(token.symbol(), "SQK");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_constructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        SqueekToken fresh = new SqueekToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_create2MintsToFactoryAndNotItsCaller() public {
        TokenFactory factory = new TokenFactory();
        bytes32 salt = keccak256("SQUEEK factory deployment test");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(factory), salt, keccak256(type(SqueekToken).creationCode)
                        )
                    )
                )
            )
        );

        vm.prank(alice, bob);
        SqueekToken deployed = factory.deploy(salt);
        assertEq(address(deployed), predicted);
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(alice), 0);
        assertEq(deployed.balanceOf(bob), 0);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.balanceOf(address(deployed)), 0);
    }

    function test_transferMovesExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 123 ether);
        assertTrue(token.transfer(alice, 123 ether));
        assertEq(token.balanceOf(alice), 123 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_fullBalanceCanMoveAndReturn() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferToContractDoesNotCallRecipient() public {
        RejectingRecipient recipient = new RejectingRecipient();
        assertTrue(token.transfer(address(recipient), 1 ether));
        assertEq(token.balanceOf(address(recipient)), 1 ether);
    }

    function test_transferAboveBalanceRevertsWithoutChanges() public {
        token.transfer(alice, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10 ether, 10 ether + 1)
        );
        vm.prank(alice);
        token.transfer(bob, 10 ether + 1);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferMaxUintRevertsWithoutOverflow() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_selfTransferStillRequiresBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(alice, 1);
    }

    function testFuzz_transferToZeroReverts(uint256 amount) public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approveEmitsEventWithoutMovingTokens() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 50 ether);
        assertTrue(token.approve(spender, 50 ether));
        assertEq(token.allowance(address(this), spender), 50 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_approvalCanBeReplacedAndRevoked() public {
        token.approve(spender, 50 ether);
        token.approve(spender, 20 ether);
        assertEq(token.allowance(address(this), spender), 20 ether);
        token.approve(spender, 0);
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_approvalBelongsOnlyToCaller() public {
        token.approve(spender, 50 ether);
        vm.prank(alice);
        token.approve(spender, 1);
        assertEq(token.allowance(address(this), spender), 50 ether);
        assertEq(token.allowance(alice, spender), 1);
    }

    function test_transferFromSpendsFiniteAllowanceAndEmitsTransfer() public {
        token.approve(spender, 50 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 20 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 20 ether));
        assertEq(token.balanceOf(alice), 20 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 20 ether);
        assertEq(token.allowance(address(this), spender), 30 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 30 ether));
        assertEq(token.balanceOf(bob), 30 ether);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maxAllowanceIsNotDecremented() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
    }

    function test_transferFromSelfConsumesAllowanceWithoutChangingBalance() public {
        token.approve(spender, 10 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 10 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_zeroTransferFromWithoutAllowanceSucceeds() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromAboveAllowanceRevertsWithoutChanges() public {
        token.approve(spender, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 10 ether, 10 ether + 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 10 ether + 1);
        assertEq(token.allowance(address(this), spender), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_transferFromAboveBalanceRestoresAllowance() public {
        vm.prank(alice);
        token.approve(spender, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 100 ether));
        vm.prank(spender);
        token.transferFrom(alice, bob, 100 ether);
        assertEq(token.allowance(alice, spender), 100 ether);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromToZeroRestoresAllowance() public {
        token.approve(spender, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 100 ether);
        assertEq(token.allowance(address(this), spender), 100 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_deployerCannotSpendHolderTokensWithoutApproval() public {
        token.transfer(alice, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        assertEq(token.balanceOf(alice), 10 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
        assertEq(token.balanceOf(bob), 10 ether);
    }

    function test_noMintBurnPauseOwnershipOrUpgradeEntryPoints() public {
        bytes[] memory calls = new bytes[](13);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", alice, 1 ether);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1 ether);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("burn(uint256)", 1 ether);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1 ether);
        calls[5] = abi.encodeWithSignature("pause()");
        calls[6] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[7] = abi.encodeWithSignature("seize(address)", alice);
        calls[8] = abi.encodeWithSignature("transferOwnership(address)", alice);
        calls[9] = abi.encodeWithSignature("upgradeTo(address)", alice);
        calls[10] = abi.encodeWithSignature("initialize(address)", alice);
        calls[11] = abi.encodeWithSignature("setMinter(address)", alice);
        calls[12] = abi.encodeWithSignature("owner()");
        token.transfer(alice, 10 ether);

        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSuccess,) = address(token).call(calls[i]);
            assertFalse(deployerSuccess, "deployer reached unexpected entry point");
            vm.prank(bob);
            (bool outsiderSuccess,) = address(token).call(calls[i]);
            assertFalse(outsiderSuccess, "outsider reached unexpected entry point");
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(alice), 10 ether);
            assertEq(token.balanceOf(bob), 0);
        }

        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
        assertEq(token.balanceOf(bob), 10 ether);
    }

    function test_plainEtherTransferReverts() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool success,) = address(token).call{value: 1 ether}("");
        assertFalse(success);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_factoryDistributionAndSubsequentTransfersAreExact() public {
        TokenFactory factory = new TokenFactory();
        SqueekToken launched = factory.deploy(keccak256("distribution"));
        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool custodian");
        address remainder = makeAddr("remainder recipient");

        vm.startPrank(address(factory));
        assertTrue(launched.transfer(distributor, SUPPLY / 10));
        assertTrue(launched.transfer(pool, SUPPLY * 80 / 100));
        assertTrue(launched.transfer(remainder, SUPPLY / 10));
        vm.stopPrank();
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), SUPPLY / 10);
        assertEq(launched.balanceOf(pool), SUPPLY * 80 / 100);
        assertEq(launched.balanceOf(remainder), SUPPLY / 10);

        vm.prank(distributor);
        assertTrue(launched.transfer(alice, SUPPLY / 10));
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.balanceOf(alice), SUPPLY / 10);

        vm.prank(pool);
        assertTrue(launched.transfer(bob, 100 ether));
        assertEq(launched.balanceOf(bob), 100 ether);
        assertEq(launched.balanceOf(pool), SUPPLY * 80 / 100 - 100 ether);
        vm.prank(bob);
        assertTrue(launched.transfer(pool, 100 ether));
        assertEq(launched.balanceOf(bob), 0);
        assertEq(launched.balanceOf(pool), SUPPLY * 80 / 100);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_runtimeHasNoPrivilegedExecutionOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
            } else {
                assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff);
            }
        }
    }

    function testFuzz_transferConservesSupply(address recipient, uint256 rawAmount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_delegatedTransferConservesSupplyAndAllowance(uint256 approved, uint256 rawAmount) public {
        uint256 maximum = approved < SUPPLY ? approved : SUPPLY;
        uint256 amount = bound(rawAmount, 0, maximum);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.allowance(address(this), spender), approved == type(uint256).max ? approved : approved - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_excessTransferRevertsAtomically(uint256 rawBalance, uint256 rawExcess) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        uint256 excess = bound(rawExcess, 1, type(uint256).max - balance);
        token.transfer(alice, balance);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, balance + excess)
        );
        vm.prank(alice);
        token.transfer(bob, balance + excess);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
