// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;


import {stdCheats, stdError} from "@std/stdlib.sol";
import {Vm} from "@std/Vm.sol";

import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {MockERC721} from "@solmate/test/utils/mocks/MockERC721.sol";
import {SafeCastLib} from "@solmate/utils/SafeCastLib.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {TWAM} from "../TWAM.sol";

contract TWAMTest is DSTestPlus, stdCheats {

    /// @dev Use forge-std Vm logic
    Vm public constant vm = Vm(HEVM_ADDRESS);

    /// @dev The TWAM Contract
    TWAM public twam;

    /// @dev The max number of tokens to be minted
    uint256 public constant TOKEN_SUPPLY = 10_000;

    /// @dev The Mock ERC721 Contract
    MockERC721 public mockToken;

    /// @notice VB is the one true coordinatooor
    address public constant COORDINATOR = 0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B;

    /// @dev The Mock ERC20 Deposit Token
    MockERC20 public depositToken;

    /// @dev A Mock ERC721 Token that has no tokens minted
    MockERC721 public badMockERC721;

    /// @notice testing suite precursors
    function setUp() public {
        /// @dev sets address(this) as the owner of the TWAM contract
        twam = new TWAM();
        assert(twam.owner() == address(this));

        depositToken = new MockERC20("Token", "TKN", 18);
        mockToken = new MockERC721("Token", "TKN");

        // Mint all erc721 tokens to the twam
        for(uint256 i = 0; i < TOKEN_SUPPLY; i++) {
            mockToken.mint(address(twam), i);
        }

        badMockERC721 = new MockERC721("Token", "TKN");
    }

    ////////////////////////////////////////////////////
    ///           SESSION MANAGEMENT LOGIC           ///
    ////////////////////////////////////////////////////

    /// @notice Test prevent duplicate sessions
    /// @dev I know this is an anti-pattern @brockelmore :p
    function testCantCreateDuplicateSessions() public {
        uint64 bn = SafeCastLib.safeCastTo64(block.number);

        // Hoax the sender and tx.origin
        address new_sender = address(1337);
        startHoax(new_sender, new_sender, type(uint256).max);

        // Expect Revert for address 0
        vm.expectRevert(
            abi.encodeWithSignature(
                "DuplicateSession(address,address)",
                new_sender,
                0
            )
        );
        twam.createSession(
            address(0), COORDINATOR, bn + 10, bn + 15,
            bn + 20, bn + 25, 100, address(depositToken), TOKEN_SUPPLY, 1
        );

        // Create a valid session
        twam.createSession(
            address(mockToken), COORDINATOR, bn + 10, bn + 15,
            bn + 20, bn + 25, 100, address(depositToken), TOKEN_SUPPLY, 1
        );

        // Expect Revert for duplicate address
        vm.expectRevert(
            abi.encodeWithSignature(
                "DuplicateSession(address,address)",
                new_sender,
                address(mockToken)
            )
        );
        twam.createSession(
            address(mockToken), COORDINATOR, bn + 10, bn + 15,
            bn + 20, bn + 25, 100, address(depositToken), TOKEN_SUPPLY, 1
        );

        vm.stopPrank();
    }

    /// @notice test creating a twam session
    function testCreateSession() public {
        uint64 blockNumber = SafeCastLib.safeCastTo64(block.number);

        // Hoax the sender and tx.origin
        address new_sender = address(1337);
        startHoax(new_sender, new_sender, type(uint256).max);

        // Expect Revert for permissionless session creations when erc721s aren't minted to this contract
        vm.expectRevert(abi.encodeWithSignature("RequireMintedERC721Tokens(uint256,uint256)", 0, TOKEN_SUPPLY));
        twam.createSession(
            address(badMockERC721),
            COORDINATOR,
            blockNumber + 10, // allocationStart,
            blockNumber + 15, // allocationEnd,
            blockNumber + 20, // mintingStart,
            blockNumber + 25, // mintingEnd,
            100, // minPrice,
            address(depositToken),
            TOKEN_SUPPLY, // maxMintingAmount,
            1 // rolloverOption
        );
        vm.stopPrank();

        // Expect Revert when bad boundaries are input
        vm.expectRevert(abi.encodeWithSignature("BadSessionBounds(uint64,uint64,uint64,uint64)", blockNumber + 20, blockNumber + 10, blockNumber + 5, blockNumber + 5));
        twam.createSession(
            address(mockToken),
            COORDINATOR,
            blockNumber + 20, // allocationStart,
            blockNumber + 10, // allocationEnd,
            blockNumber + 5, // mintingStart,
            blockNumber + 5, // mintingEnd,
            100, // minPrice,
            address(depositToken),
            TOKEN_SUPPLY, // maxMintingAmount,
            1 // rolloverOption
        );

        // Expect Revert when bad boundaries are input
        vm.expectRevert(abi.encodeWithSignature("BadSessionBounds(uint64,uint64,uint64,uint64)", blockNumber + 10, blockNumber + 5, blockNumber + 20, blockNumber + 25));
        twam.createSession(
            address(mockToken),
            COORDINATOR,
            blockNumber + 10, // allocationStart,
            blockNumber + 5, // allocationEnd,
            blockNumber + 20, // mintingStart,
            blockNumber + 25, // mintingEnd,
            100, // minPrice,
            address(depositToken),
            TOKEN_SUPPLY, // maxMintingAmount,
            1 // rolloverOption
        );

        // Expect Revert when bad boundaries are input
        vm.expectRevert(abi.encodeWithSignature("BadSessionBounds(uint64,uint64,uint64,uint64)", blockNumber + 10, blockNumber + 15, blockNumber + 5, blockNumber + 25));
        twam.createSession(
            address(mockToken),
            COORDINATOR,
            blockNumber + 10, // allocationStart,
            blockNumber + 15, // allocationEnd,
            blockNumber + 5, // mintingStart,
            blockNumber + 25, // mintingEnd,
            100, // minPrice,
            address(depositToken),
            TOKEN_SUPPLY, // maxMintingAmount,
            1 // rolloverOption
        );

        // Expect Revert when bad boundaries are input
        vm.expectRevert(abi.encodeWithSignature("BadSessionBounds(uint64,uint64,uint64,uint64)", blockNumber + 10, blockNumber + 15, blockNumber + 20, blockNumber + 15));
        twam.createSession(
            address(mockToken),
            COORDINATOR,
            blockNumber + 10, // allocationStart,
            blockNumber + 15, // allocationEnd,
            blockNumber + 20, // mintingStart,
            blockNumber + 15, // mintingEnd,
            100, // minPrice,
            address(depositToken),
            TOKEN_SUPPLY, // maxMintingAmount,
            1 // rolloverOption
        );

        // Create a valid session
        twam.createSession(
            address(mockToken),
            COORDINATOR,
            blockNumber + 10, // allocationStart,
            blockNumber + 15, // allocationEnd,
            blockNumber + 20, // mintingStart,
            blockNumber + 25, // mintingEnd,
            100, // minPrice,
            address(depositToken),
            TOKEN_SUPPLY, // maxMintingAmount,
            1 // rolloverOption
        );
        TWAM.Session memory sess = twam.getSession(0);

        // Validate Session Parameters
        assert(sess.token == address(mockToken));
        assert(sess.coordinator == COORDINATOR);
        assert(sess.allocationStart == blockNumber + 10);
        assert(sess.allocationEnd == blockNumber + 15);
        assert(sess.mintingStart == blockNumber + 20);
        assert(sess.mintingEnd == blockNumber + 25);
        assert(sess.resultPrice == 0);
        assert(sess.minPrice == 100);
        assert(sess.depositToken == address(depositToken));
        assert(sess.depositAmount == 0);
        assert(sess.maxMintingAmount == TOKEN_SUPPLY);
        assert(sess.rolloverOption == 1);
    }

    /// @notice Tests rolling over a session
    function testRollover() public {
        uint64 blockNumber = SafeCastLib.safeCastTo64(block.number);

        // Expect Revert for an invalid sessionId
        vm.expectRevert(abi.encodeWithSignature("InvalidSession(uint256)", 0));
        twam.rollover(0);

        // Create a valid session
        twam.createSession(
            address(mockToken),
            COORDINATOR,
            blockNumber + 10, // allocationStart,
            blockNumber + 15, // allocationEnd,
            blockNumber + 20, // mintingStart,
            blockNumber + 25, // mintingEnd,
            100, // minPrice,
            address(depositToken),
            TOKEN_SUPPLY, // maxMintingAmount,
            1 // rolloverOption
        );

        // Expect Revert when not called from the coordinator context
        vm.expectRevert(abi.encodeWithSignature("InvalidCoordinator(address,address)", address(this), COORDINATOR));
        twam.rollover(0);

        // Hoax from the COORDINATOR context
        startHoax(COORDINATOR, COORDINATOR, type(uint256).max);

        // Expect Revert when the mint isn't over
        vm.expectRevert(abi.encodeWithSignature("MintingNotOver(uint256,uint64)", blockNumber, blockNumber + 25));
        twam.rollover(0);

        // Roll the block height
        vm.roll(blockNumber + 25);

        // The rollover should succeed now that the minting period is over
        twam.rollover(0);

        vm.stopPrank();
    }

    /// @notice Coordinators are able to withdraw their rewards
    function testWithdrawRewards() public {
        uint64 blockNumber = SafeCastLib.safeCastTo64(block.number);

        // Create a valid session
        twam.createSession(
            address(mockToken),
            COORDINATOR,
            blockNumber + 10, // allocationStart,
            blockNumber + 15, // allocationEnd,
            blockNumber + 20, // mintingStart,
            blockNumber + 25, // mintingEnd,
            1, // minPrice,
            address(depositToken),
            TOKEN_SUPPLY, // maxMintingAmount,
            1 // rolloverOption
        );

        // Jump to allocation period
        vm.roll(blockNumber + 11);

        // Create Mock Users
        address firstUser = address(1);
        address secondUser = address(2);

        // Give them depositToken balances
        depositToken.mint(firstUser, 1e18);
        depositToken.mint(secondUser, 1e18);

        // Mock first user deposits
        startHoax(firstUser, firstUser, type(uint256).max);
        depositToken.approve(address(twam), 1e18); // Approve the TWAM to transfer the depositToken
        twam.deposit(0, TOKEN_SUPPLY);
        assert(depositToken.balanceOf(address(twam)) == TOKEN_SUPPLY);
        vm.stopPrank();

        // Mock second user deposits
        startHoax(secondUser, secondUser, type(uint256).max);
        depositToken.approve(address(twam), 1e18); // Approve the TWAM to transfer the depositToken
        twam.deposit(0, TOKEN_SUPPLY);
        assert(depositToken.balanceOf(address(twam)) == 2 * TOKEN_SUPPLY);
        vm.stopPrank();

        // Jump to minting period
        vm.roll(blockNumber + 21);

        // Mock first user mints
        startHoax(firstUser, firstUser, type(uint256).max);
        twam.mint(0, TOKEN_SUPPLY);
        assert(mockToken.balanceOf(address(twam)) == TOKEN_SUPPLY / 2);
        assert(mockToken.balanceOf(address(firstUser)) == TOKEN_SUPPLY / 2);
        assert(twam.rewards(COORDINATOR, address(depositToken)) == TOKEN_SUPPLY);
        assert(depositToken.balanceOf(address(twam)) == 2 * TOKEN_SUPPLY);
        vm.stopPrank();

        // Mock second user mints
        startHoax(secondUser, secondUser, type(uint256).max);
        twam.mint(0, TOKEN_SUPPLY);
        assert(mockToken.balanceOf(address(twam)) == 0);
        assert(mockToken.balanceOf(address(secondUser)) == TOKEN_SUPPLY / 2);
        assert(twam.rewards(COORDINATOR, address(depositToken)) == 2 * TOKEN_SUPPLY);
        assert(depositToken.balanceOf(address(twam)) == 2 * TOKEN_SUPPLY);
        vm.stopPrank();

        // Jump to post-mint
        vm.roll(blockNumber + 26);

        // Try to withdraw rewards
        startHoax(COORDINATOR, COORDINATOR, type(uint256).max);
        assert(depositToken.balanceOf(COORDINATOR) == 0);
        assert(depositToken.balanceOf(address(twam)) == 2 * TOKEN_SUPPLY);
        assert(twam.rewards(COORDINATOR, address(depositToken)) == 2 * TOKEN_SUPPLY);
        twam.withdrawRewards(address(depositToken));
        assert(depositToken.balanceOf(COORDINATOR) == 2 * TOKEN_SUPPLY);
        vm.stopPrank();
    }

    ////////////////////////////////////////////////////
    ///           SESSION ALLOCATION PERIOD          ///
    ////////////////////////////////////////////////////

    /// @notice Test deposits
    function testDeposit() public {
        uint64 blockNumber = SafeCastLib.safeCastTo64(block.number);

        // Expect Revert when session isn't created
        vm.expectRevert(abi.encodeWithSignature("InvalidSession(uint256)", 0));
        twam.deposit(0, TOKEN_SUPPLY);

        // Create a valid session
        twam.createSession(
            address(mockToken),
            COORDINATOR,
            blockNumber + 10, // allocationStart,
            blockNumber + 15, // allocationEnd,
            blockNumber + 20, // mintingStart,
            blockNumber + 25, // mintingEnd,
            1, // minPrice,
            address(depositToken),
            TOKEN_SUPPLY, // maxMintingAmount,
            1 // rolloverOption
        );

        // Jump to after the allocation period
        vm.roll(blockNumber + 16);

        // Expect Revert when we are after the allocation period
        vm.expectRevert(
            abi.encodeWithSignature(
                "NonAllocation(uint256,uint64,uint64)",
                blockNumber + 16,
                blockNumber + 10,
                blockNumber + 15
            )
        );
        twam.deposit(0, TOKEN_SUPPLY);

        // Reset to before the allocation period
        vm.roll(blockNumber + 5);

        // Expect Revert when we are before the allocation period
        vm.expectRevert(
            abi.encodeWithSignature(
                "NonAllocation(uint256,uint64,uint64)",
                blockNumber + 5,
                blockNumber + 10,
                blockNumber + 15
            )
        );
        twam.deposit(0, TOKEN_SUPPLY);

        // Jump to allocation period
        vm.roll(blockNumber + 11);

        // Create Mock Users
        address firstUser = address(1);
        address secondUser = address(2);

        // Give them depositToken balances
        depositToken.mint(firstUser, 1e18);
        depositToken.mint(secondUser, 1e18);

        // Mock first user deposits
        startHoax(firstUser, firstUser, type(uint256).max);
        depositToken.approve(address(twam), 1e18); // Approve the TWAM to transfer the depositToken
        twam.deposit(0, TOKEN_SUPPLY);
        assert(depositToken.balanceOf(address(twam)) == TOKEN_SUPPLY);
        vm.stopPrank();

        // Mock second user deposits
        startHoax(secondUser, secondUser, type(uint256).max);
        depositToken.approve(address(twam), 1e18); // Approve the TWAM to transfer the depositToken
        twam.deposit(0, TOKEN_SUPPLY);
        assert(depositToken.balanceOf(address(twam)) == 2 * TOKEN_SUPPLY);
        vm.stopPrank();
    }

    /// @notice Test withdrawals
    function testWithdrawals() public {
        uint64 blockNumber = SafeCastLib.safeCastTo64(block.number);

        // Expect Revert when session isn't created
        vm.expectRevert(abi.encodeWithSignature("InvalidSession(uint256)", 0));
        twam.withdraw(0, TOKEN_SUPPLY);

        // Create a valid session
        twam.createSession(
            address(mockToken),
            COORDINATOR,
            blockNumber + 10, // allocationStart,
            blockNumber + 15, // allocationEnd,
            blockNumber + 20, // mintingStart,
            blockNumber + 25, // mintingEnd,
            1, // minPrice,
            address(depositToken),
            TOKEN_SUPPLY, // maxMintingAmount,
            1 // rolloverOption
        );

        // Jump to after the allocation period
        vm.roll(blockNumber + 16);

        // Expect Revert when we are after the allocation period
        vm.expectRevert(
            abi.encodeWithSignature(
                "NonAllocation(uint256,uint64,uint64)",
                blockNumber + 16,
                blockNumber + 10,
                blockNumber + 15
            )
        );
        twam.withdraw(0, TOKEN_SUPPLY);

        // Reset to before the allocation period
        vm.roll(blockNumber + 5);

        // Expect Revert when we are before the allocation period
        vm.expectRevert(
            abi.encodeWithSignature(
                "NonAllocation(uint256,uint64,uint64)",
                blockNumber + 5,
                blockNumber + 10,
                blockNumber + 15
            )
        );
        twam.withdraw(0, TOKEN_SUPPLY);

        // Jump to allocation period
        vm.roll(blockNumber + 11);

        // Create Mock Users
        address firstUser = address(1);
        address secondUser = address(2);

        // Give them depositToken balances
        depositToken.mint(firstUser, 1e18);
        depositToken.mint(secondUser, 1e18);

        // Mock first user deposits and withdrawals
        startHoax(firstUser, firstUser, type(uint256).max);
        depositToken.approve(address(twam), 1e18); // Approve the TWAM to transfer the depositToken
        twam.deposit(0, TOKEN_SUPPLY);
        assert(depositToken.balanceOf(address(twam)) == TOKEN_SUPPLY);
        twam.withdraw(0, TOKEN_SUPPLY);
        assert(depositToken.balanceOf(address(twam)) == 0);
        vm.stopPrank();

        // Mock second user deposits and withdrawals
        startHoax(secondUser, secondUser, type(uint256).max);
        depositToken.approve(address(twam), 1e18); // Approve the TWAM to transfer the depositToken
        twam.deposit(0, TOKEN_SUPPLY);
        assert(depositToken.balanceOf(address(twam)) == TOKEN_SUPPLY);
        twam.withdraw(0, TOKEN_SUPPLY);
        assert(depositToken.balanceOf(address(twam)) == 0);
        vm.stopPrank();
    }

    /// @notice Tests users can withdraw after minting ends when session rollover = 3
    function testWithdrawRollover3() public {
        uint64 blockNumber = SafeCastLib.safeCastTo64(block.number);

        // Create a valid session
        twam.createSession(
            address(mockToken),
            COORDINATOR,
            blockNumber + 10, // allocationStart,
            blockNumber + 15, // allocationEnd,
            blockNumber + 20, // mintingStart,
            blockNumber + 25, // mintingEnd,
            1, // minPrice,
            address(depositToken),
            TOKEN_SUPPLY, // maxMintingAmount,
            3 // rolloverOption
        );

        // Jump to allocation period
        vm.roll(blockNumber + 11);

        // Create Mock Users
        address firstUser = address(1);
        depositToken.mint(firstUser, 1e18);

        // Mock user deposits
        startHoax(firstUser, firstUser, type(uint256).max);
        depositToken.approve(address(twam), 1e18); // Approve the TWAM to transfer the depositToken
        twam.deposit(0, TOKEN_SUPPLY);
        assert(depositToken.balanceOf(address(twam)) == TOKEN_SUPPLY);
        vm.stopPrank();

        // Jump to after the mint period
        vm.roll(blockNumber + 26);

        // Mock user withdrawal
        startHoax(firstUser, firstUser, type(uint256).max);
        assert(depositToken.balanceOf(address(twam)) == TOKEN_SUPPLY);
        twam.withdraw(0, TOKEN_SUPPLY);
        assert(depositToken.balanceOf(address(twam)) == 0);
        vm.stopPrank();
    }

    ////////////////////////////////////////////////////
    ///            SESSION MINTING PERIOD            ///
    ////////////////////////////////////////////////////

    /// @notice Tests minting period
    function testMints() public {
        uint64 bn = SafeCastLib.safeCastTo64(block.number);

        // User can't mint a non-existent session
        vm.expectRevert(abi.encodeWithSignature("InvalidSession(uint256)", 0));
        twam.mint(0, TOKEN_SUPPLY);

        twam.createSession(
            address(mockToken), COORDINATOR, bn + 10, bn + 15,
            bn + 20, bn + 25, 1, address(depositToken),
            TOKEN_SUPPLY, 1
        );

        // Jump to allocation period
        vm.roll(bn + 11);

        // Create Users
        address firstUser = address(1);
        address secondUser = address(2);
        depositToken.mint(firstUser, 1e18);
        depositToken.mint(secondUser, 1e18);

        // Users Deposit
        startHoax(firstUser, firstUser, type(uint256).max);
        depositToken.approve(address(twam), 1e18);
        twam.deposit(0, TOKEN_SUPPLY);
        vm.stopPrank();
        startHoax(secondUser, secondUser, type(uint256).max);
        depositToken.approve(address(twam), 1e18);
        twam.deposit(0, TOKEN_SUPPLY);

        // User can't mint before minting period starts
        vm.expectRevert(abi.encodeWithSignature(
            "NonMinting(uint256,uint64,uint64)",
            block.number, bn + 20, bn +25
        ));
        twam.mint(0, TOKEN_SUPPLY);

        vm.stopPrank();

        // Jump to minting period
        vm.roll(bn + 21);

        // Mock first user mints
        startHoax(firstUser, firstUser, type(uint256).max);

        // User shouldn't be able to mint more than their deposits
        vm.expectRevert(abi.encodeWithSignature(
            "InsufficientDesposits(address,uint256,uint256)",
            firstUser, TOKEN_SUPPLY, 2 * TOKEN_SUPPLY
        ));
        twam.mint(0, 2 * TOKEN_SUPPLY);

        // Then they should successfully be able to mint
        twam.mint(0, TOKEN_SUPPLY);
        assert(mockToken.balanceOf(address(twam)) == TOKEN_SUPPLY / 2);
        assert(mockToken.balanceOf(address(firstUser)) == TOKEN_SUPPLY / 2);
        assert(twam.rewards(COORDINATOR, address(depositToken)) == TOKEN_SUPPLY);
        assert(depositToken.balanceOf(address(twam)) == 2 * TOKEN_SUPPLY);

        // Check that the session `resultPrice` is correct
        TWAM.Session memory sess = twam.getSession(0);
        assert(sess.resultPrice == 2);
        vm.stopPrank();

        // Mock second user mints
        startHoax(secondUser, secondUser, type(uint256).max);

        // User shouldn't be able to mint more than their deposits
        vm.expectRevert(abi.encodeWithSignature(
            "InsufficientDesposits(address,uint256,uint256)",
            secondUser, TOKEN_SUPPLY, 2 * TOKEN_SUPPLY
        ));
        twam.mint(0, 2 * TOKEN_SUPPLY);

        twam.mint(0, TOKEN_SUPPLY);
        assert(mockToken.balanceOf(address(twam)) == 0);
        assert(mockToken.balanceOf(address(secondUser)) == TOKEN_SUPPLY / 2);
        assert(twam.rewards(COORDINATOR, address(depositToken)) == 2 * TOKEN_SUPPLY);
        assert(depositToken.balanceOf(address(twam)) == 2 * TOKEN_SUPPLY);

        // Check that the session `resultPrice` is still correct
        TWAM.Session memory sess2 = twam.getSession(0);
        assert(sess2.resultPrice == 2);

        vm.stopPrank();
    }

    /// @notice Tests forgoing a mint
    function testForgo() public {
        uint64 bn = SafeCastLib.safeCastTo64(block.number);

        // User can't mint a non-existent session
        vm.expectRevert(abi.encodeWithSignature("InvalidSession(uint256)", 0));
        twam.forgo(0, TOKEN_SUPPLY);

        twam.createSession(
            address(mockToken), COORDINATOR, bn + 10, bn + 15,
            bn + 20, bn + 25, 1, address(depositToken),
            TOKEN_SUPPLY, 1
        );

        // Jump to allocation period
        vm.roll(bn + 11);

        // Create Users
        address firstUser = address(1);
        address secondUser = address(2);
        depositToken.mint(firstUser, 1e18);
        depositToken.mint(secondUser, 1e18);

        // Users Deposit
        startHoax(firstUser, firstUser, type(uint256).max);
        depositToken.approve(address(twam), 1e18);
        twam.deposit(0, TOKEN_SUPPLY);
        vm.stopPrank();
        startHoax(secondUser, secondUser, type(uint256).max);
        depositToken.approve(address(twam), 1e18);
        twam.deposit(0, TOKEN_SUPPLY);

        // User can't forgo before minting period starts
        vm.expectRevert(abi.encodeWithSignature(
            "NonMinting(uint256,uint64,uint64)",
            block.number, bn + 20, bn +25
        ));
        twam.forgo(0, TOKEN_SUPPLY);

        vm.stopPrank();

        // Jump to minting period
        vm.roll(bn + 21);

        // Mock first user mints
        startHoax(firstUser, firstUser, type(uint256).max);

        // Then they should successfully be able to mint
        twam.forgo(0, TOKEN_SUPPLY);
        assert(mockToken.balanceOf(address(twam)) == TOKEN_SUPPLY);
        assert(mockToken.balanceOf(address(firstUser)) == 0);
        assert(depositToken.balanceOf(address(twam)) == TOKEN_SUPPLY);

        // Check that the session `resultPrice` is correct
        TWAM.Session memory sess = twam.getSession(0);
        assert(sess.resultPrice == 2);
        vm.stopPrank();

        // Mock second user mints
        startHoax(secondUser, secondUser, type(uint256).max);

        twam.forgo(0, TOKEN_SUPPLY);
        assert(mockToken.balanceOf(address(twam)) == TOKEN_SUPPLY);
        assert(mockToken.balanceOf(address(secondUser)) == 0);
        assert(depositToken.balanceOf(address(twam)) == 0);

        // Check that the session `resultPrice` is still correct
        TWAM.Session memory sess2 = twam.getSession(0);
        assert(sess2.resultPrice == 2);
        vm.stopPrank();
    }

    ////////////////////////////////////////////////////
    ///            SESSION MINTING PERIOD            ///
    ////////////////////////////////////////////////////

    /// @notice Tests can fetch sessions by Id
    function testGetSession() public {
        uint64 bn = SafeCastLib.safeCastTo64(block.number);

        // This should be an empty session since none have been created
        TWAM.Session memory sess = twam.getSession(0);
        // Validate Session Parameters
        assert(sess.token == address(0));
        assert(sess.coordinator == address(0));
        assert(sess.allocationStart == 0);
        assert(sess.allocationEnd == 0);
        assert(sess.mintingStart == 0);
        assert(sess.mintingEnd == 0);
        assert(sess.resultPrice == 0);
        assert(sess.minPrice == 0);
        assert(sess.depositToken == address(0));
        assert(sess.depositAmount == 0);
        assert(sess.maxMintingAmount == 0);
        assert(sess.rolloverOption == 0);

        // Create multiple valid sessions
        twam.createSession(
            address(mockToken),
            COORDINATOR,
            bn + 10,
            bn + 15,
            bn + 20,
            bn + 25,
            1,
            address(depositToken),
            TOKEN_SUPPLY,
            3
        );

        // Validate that we can read these session parameters corectly
        TWAM.Session memory sess2 = twam.getSession(0);
        assert(sess2.token == address(mockToken));
        assert(sess2.coordinator == COORDINATOR);
        assert(sess2.allocationStart == bn + 10);
        assert(sess2.allocationEnd == bn + 15);
        assert(sess2.mintingStart == bn + 20);
        assert(sess2.mintingEnd == bn + 25);
        assert(sess2.resultPrice == 0);
        assert(sess2.minPrice == 1);
        assert(sess2.depositToken == address(depositToken));
        assert(sess2.depositAmount == 0);
        assert(sess2.maxMintingAmount == TOKEN_SUPPLY);
        assert(sess2.rolloverOption == 3);
    }
}
