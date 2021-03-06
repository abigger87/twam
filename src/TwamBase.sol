// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import {Clone} from "@clones/Clone.sol";
import {SafeCastLib} from "@solmate/utils/SafeCastLib.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";

import {IERC20} from "./interfaces/IERC20.sol";
import {IERC721} from "./interfaces/IERC721.sol";

////////////////////////////////////////////////////
///                 CUSTOM ERRORS                ///
////////////////////////////////////////////////////

/// Invalid Session
/// @param sessionId The session's id
error InvalidSession(uint256 sessionId);

/// Not during the Allocation Period
/// @param blockNumber block.number
/// @param allocationStart The block number that marks when the allocation starts
/// @param allocationEnd The block number that marks when the allocation ends
error NonAllocation(uint256 blockNumber, uint64 allocationStart, uint64 allocationEnd);

/// Not during the Minting Period
/// @param blockNumber block.number
/// @param mintingStart The block number that marks when the minting period starts
/// @param mintingEnd The block number that marks when the minting period ends
error NonMinting(uint256 blockNumber, uint64 mintingStart, uint64 mintingEnd);

/// Make sure the sender has enough deposits
/// @param sender The message sender
/// @param deposits The user's deposits in the session
/// @param amount The amount a user want's to mint with
error InsufficientDesposits(address sender, uint256 deposits, uint256 amount);

/// The Minting Period is not Over
/// @param blockNumber The current block.number
/// @param mintingEnd When the session minting period ends
error MintingNotOver(uint256 blockNumber, uint64 mintingEnd);

/// Invalid Coordinator
/// @param sender The msg sender
/// @param coordinator The expected session coordinator
error InvalidCoordinator(address sender, address coordinator);

////////////////////////////////////////////////////
///                     TWAM                     ///
////////////////////////////////////////////////////

/// @title TwamBase
/// @notice Time Weighted Asset Minting Base Clone
/// @author Andreas Bigger <andreas@nascent.xyz>
contract TwamBase is Clone {
  using FixedPointMathLib for uint256;

  /// @dev Immutable Session Variables are stored in Calldata using ClonesWithImmutableArgs

  /// @notice Maps a session to the amount of deposits
  mapping(uint256 => uint256) public totalDeposits;

  /// @notice Maps a session id to the resulting session price
  mapping(uint256 => uint256) public resultPrice;

  /// @notice Maps a session id to the next token id to mint
  mapping(uint256 => uint256) public nextMintId;

  /// @notice Maps a user and session id to their deposits
  mapping(address => mapping(uint256 => uint256)) public deposits;

  /// @notice Session Rewards for Coordinators
  /// @dev Maps coordinator => token => rewardAmount
  mapping(address => mapping(address => uint256)) public rewards;

  /// @notice Loss Penalty for each depositor
  /// @dev Fixed-point number where YAD represents 100%
  /// @dev Updates calculated using weighted average
  /// @dev Maps user => session id => lossPenalty
  mapping(address => mapping(uint256 => uint256)) public lossPenalty;

  /// @notice The Loss Penalty base unit
  uint256 public constant YAD = 1e8;

  /// @notice Token Ids for the ERC721s
  mapping(address => uint256) private tokenIds;

  /// @dev A rollover offset
  /// @dev Maps a session Id to the rolloverOffset
  /// @dev The rolloverOffset equals block.timestamp when rollover() is called
  mapping(uint256 => uint256) private rolloverOffset;

  ////////////////////////////////////////////////////
  ///           SESSION MANAGEMENT LOGIC           ///
  ////////////////////////////////////////////////////

  /// @notice Allows the coordinator to rollover 
  /// @notice Requires the minting period to be over
  function rollover() public {
    // Read Calldata Immutables
    address coordinator = readCoordinator();
    uint64 mintingEnd = readMintingEnd();
    uint256 sessionId = readSessionId();
    uint8 rolloverOption = readRolloverOption();

    // Validate Coordinator
    if (msg.sender != coordinator) {
      revert InvalidCoordinator(msg.sender, coordinator);
    }

    // MSTORE timestamp is cheaper than double calls
    uint256 timestamp = block.timestamp;

    // Require Minting to be complete
    if (timestamp < mintingEnd) {
      revert MintingNotOver(timestamp, mintingEnd);
    }

    // Rollover Options
    // 1. Restart the twam
    // 2. Mint at resulting price or minimum if not reached
    // 3. Close Session
    if(rolloverOption != 3) {
      // For both options 1 & 2, we can just set the rolloverOffset
      // and check it inside our functions
      rolloverOffset[sessionId] = timestamp;
    }
  }

  /// @notice Allows the coordinator to withdraw session rewards
  function withdrawRewards() public {
    // Read Calldata Immutables
    address depositToken = readDepositToken();

    // Transfer rewards
    uint256 rewardAmount = rewards[msg.sender][depositToken];
    rewards[msg.sender][depositToken] = 0;
    IERC20(depositToken).transfer(msg.sender, rewardAmount);
  }

  ////////////////////////////////////////////////////
  ///           SESSION ALLOCATION PERIOD          ///
  ////////////////////////////////////////////////////

  /// @notice Deposit a deposit token into a session
  /// @dev requires approval of the deposit token
  /// @param amount The amount of the deposit token to deposit
  function deposit(uint256 amount) public {
    // Read Calldata Immutables
    uint256 sessionId = readSessionId();
    uint64 allocationStart = readAllocationStart();
    uint64 allocationEnd = readAllocationEnd();
    address depositToken = readDepositToken();

    // MSTORE timestamp is cheaper than double calls
    uint256 timestamp = block.timestamp;
  
    // Make sure the session is in the allocation period
    if (timestamp > allocationEnd || timestamp < allocationStart) {
      revert NonAllocation(timestamp, allocationStart, allocationEnd);
    }

    // Update a user's loss penalty
    uint256 currLossPenalty = lossPenalty[msg.sender][sessionId];

    // Calculate Loss Penalty
    uint256 newLossPenalty = simulateLossPenalty(amount, allocationStart, allocationEnd, timestamp);
    if (newLossPenalty > YAD) newLossPenalty = YAD;

    // Set the penalty if 0
    if(currLossPenalty == 0) {
      lossPenalty[msg.sender][sessionId] = newLossPenalty;
    } else {
      // Calculate a weighted penalty based on amount
      uint256 user_deposits = deposits[msg.sender][sessionId];
      lossPenalty[msg.sender][sessionId] = (
        (newLossPenalty * amount)
        + (currLossPenalty * user_deposits)
      ) / (user_deposits + amount);
    }

    // Transfer the token to this contract
    IERC20(depositToken).transferFrom(msg.sender, address(this), amount);

    // Update the user's deposit amount and total session deposits
    deposits[msg.sender][sessionId] += amount;
    totalDeposits[sessionId] += amount;
  }

  /// @notice Withdraws a deposit token from a session
  /// @dev Only permitted when the session is over
  /// @param amount The amount of the deposit token to withdraw
  function withdraw(uint256 amount) public {
    // Read Calldata Immutables
    uint256 sessionId = readSessionId();
    uint64 allocationStart = readAllocationStart();
    uint64 allocationEnd = readAllocationEnd();
    uint64 mintingStart = readMintingStart();
    uint64 mintingEnd = readMintingEnd();
    address depositToken = readDepositToken();
    uint8 rolloverOption = readRolloverOption();

    // MSTORE timestamp is cheaper than double calls
    uint256 timestamp = block.timestamp;

    // Allows a user to withdraw deposits if session ends
    if (timestamp < mintingEnd || rolloverOption != 3) {
      revert NonAllocation(timestamp, allocationStart, allocationEnd);
    }

    // Get the loss penalty
    uint256 finalLossPenalty = lossPenalty[msg.sender][sessionId];

    // Make sure the user has enough deposits to mint at least one, otherwise forfeit loss penalty
    uint256 totalUserDeposits = deposits[msg.sender][sessionId];
    uint256 finalPrice = resultPrice[sessionId]; 
    if (totalUserDeposits < finalPrice) {
      finalLossPenalty = 0;
    }

    // Update the user's deposit amount and total session deposits
    // This will revert on underflow so no need to check amount
    deposits[msg.sender][sessionId] -= amount;
    totalDeposits[sessionId] -= amount;

    // Transfer the token to this contract
    IERC20(depositToken).transfer(msg.sender, amount - ((finalLossPenalty * amount) / YAD));
  }

  ////////////////////////////////////////////////////
  ///            SESSION MINTING PERIOD            ///
  ////////////////////////////////////////////////////

  /// @notice Mints tokens during minting period
  /// @param amount The amount of deposits to mint with
  function mint(uint256 amount) public {
    // Read Calldata Immutables
    address token = readToken();
    address coordinator = readCoordinator();
    uint256 sessionId = readSessionId();
    uint64 mintingStart = readMintingStart();
    uint64 mintingEnd = readMintingEnd();
    address depositToken = readDepositToken();
    uint256 maxMintingAmount = readMaxMintingAmount();
    uint256 minPrice = readMinPrice();
    address twamFactory = readTwamFactoryAddress();

    // MSTORE timestamp is cheaper than double calls
    uint256 timestamp = block.timestamp;

    // Make sure the session is in the minting period
    if (timestamp > mintingEnd || timestamp < mintingStart) {
      revert NonMinting(timestamp, mintingStart, mintingEnd);
    }

    // Cache the result price
    if(resultPrice[sessionId] == 0) {
      // incur an additional SLOAD since this branch occurs once
      resultPrice[sessionId] = totalDeposits[sessionId] / maxMintingAmount;
    }

    // Calculate the mint price
    uint256 mintPrice = resultPrice[sessionId];
    if(mintPrice < minPrice) mintPrice = minPrice;

    // Validate sender deposits and amount
    if (deposits[msg.sender][sessionId] < amount || amount < mintPrice) {
      // incur the additional SLOAD at the cost of a failed tx
      revert InsufficientDesposits(msg.sender, deposits[msg.sender][sessionId], amount);
    }

    // Get the next token Id to mint
    uint256 nextTokenToMint = nextMintId[sessionId];
    
    // Reverts on underflow
    uint256 numberToMint = amount / mintPrice;

    // Reduce deposits
    deposits[msg.sender][sessionId] -= numberToMint * mintPrice;
    totalDeposits[sessionId] -= numberToMint * mintPrice;

    // Update the next id to mint
    nextMintId[sessionId] += numberToMint;

    // Mint
    for(uint256 i = nextTokenToMint; i < nextTokenToMint + numberToMint; i++) {
      IERC721(token).safeTransferFrom(twamFactory, msg.sender, i);
    }

    // Only give rewards to coordinator once the ERC721 Tokens are transferred
    rewards[coordinator][depositToken] += numberToMint * mintPrice;
  }

  /// @notice Allows a user to forgo their mint allocation
  /// @param amount The amount of deposits to withdraw
  function forgo(uint256 amount) public {
    // Read Calldata Immutables
    uint256 sessionId = readSessionId();
    uint64 mintingStart = readMintingStart();
    uint64 mintingEnd = readMintingEnd();
    address depositToken = readDepositToken();
    uint256 maxMintingAmount = readMaxMintingAmount();

    // MSTORE timestamp is cheaper than double calls
    uint256 timestamp = block.timestamp;

    // Make sure the session is in the minting period
    if (timestamp > mintingEnd || timestamp < mintingStart) {
      revert NonMinting(timestamp, mintingStart, mintingEnd);
    }

    // Cache the result price
    if(resultPrice[sessionId] == 0) {
      // incur an additional SLOAD since this branch occurs once
      resultPrice[sessionId] = totalDeposits[sessionId] / maxMintingAmount;
    }

    // Get the loss penalty
    uint256 finalLossPenalty = lossPenalty[msg.sender][sessionId];

    // Make sure the user has enough deposits to mint at least one, otherwise forfeit loss penalty
    uint256 totalUserDeposits = deposits[msg.sender][sessionId];
    uint256 finalPrice = resultPrice[sessionId]; 
    if (totalUserDeposits < finalPrice) {
      finalLossPenalty = 0;
    }

    // Update the user's deposit amount and total session deposits
    // This will revert on underflow so no need to check amount
    deposits[msg.sender][sessionId] -= amount;
    totalDeposits[sessionId] -= amount;

    // Transfer the token to this contract
    IERC20(depositToken).transfer(msg.sender, amount - ((finalLossPenalty * amount) / YAD));
  }

  ////////////////////////////////////////////////////
  ///                 LOSS PENALTY                 ///
  ////////////////////////////////////////////////////

  /// @notice Calculates the Loss Penalty for a depositor
  /// @param amount The amount of `depositToken`
  /// @return penalty A fixed-point uint256 representing the loss penalty 
  function simulateLossPenalty(
    uint256 amount,
    uint64 allocStart,
    uint64 allocEnd,
    uint256 timestamp
  ) public view returns(uint256 penalty) {
    // Calculate log of ceiling
    /// @dev end - 1, requires a manual check if allocEnd == block.timestamp, penalty = 1
    uint256 r = log2(YAD) / log2((allocEnd - 1) - allocStart);
    penalty = (timestamp - allocStart) ** r;
  }

  /// @dev Calculates the log base-2 using < 700 gas
  function log2(uint256 x) internal view returns (uint256 y){
   assembly {
      let arg := x
      x := sub(x,1)
      x := or(x, div(x, 0x02))
      x := or(x, div(x, 0x04))
      x := or(x, div(x, 0x10))
      x := or(x, div(x, 0x100))
      x := or(x, div(x, 0x10000))
      x := or(x, div(x, 0x100000000))
      x := or(x, div(x, 0x10000000000000000))
      x := or(x, div(x, 0x100000000000000000000000000000000))
      x := add(x, 1)
      let m := mload(0x40)
      mstore(m,           0xf8f9cbfae6cc78fbefe7cdc3a1793dfcf4f0e8bbd8cec470b6a28a7a5a3e1efd)
      mstore(add(m,0x20), 0xf5ecf1b3e9debc68e1d9cfabc5997135bfb7a7a3938b7b606b5b4b3f2f1f0ffe)
      mstore(add(m,0x40), 0xf6e4ed9ff2d6b458eadcdf97bd91692de2d4da8fd2d0ac50c6ae9a8272523616)
      mstore(add(m,0x60), 0xc8c0b887b0a8a4489c948c7f847c6125746c645c544c444038302820181008ff)
      mstore(add(m,0x80), 0xf7cae577eec2a03cf3bad76fb589591debb2dd67e0aa9834bea6925f6a4a2e0e)
      mstore(add(m,0xa0), 0xe39ed557db96902cd38ed14fad815115c786af479b7e83247363534337271707)
      mstore(add(m,0xc0), 0xc976c13bb96e881cb166a933a55e490d9d56952b8d4e801485467d2362422606)
      mstore(add(m,0xe0), 0x753a6d1b65325d0c552a4d1345224105391a310b29122104190a110309020100)
      mstore(0x40, add(m, 0x100))
      let magic := 0x818283848586878898a8b8c8d8e8f929395969799a9b9d9e9faaeb6bedeeff
      let shift := 0x100000000000000000000000000000000000000000000000000000000000000
      let a := div(mul(x, magic), shift)
      y := div(mload(add(m,sub(255,a))), shift)
      y := add(y, mul(256, gt(arg, 0x8000000000000000000000000000000000000000000000000000000000000000)))
    }  
  }


  ////////////////////////////////////////////////////
  ///            READ SESSION PARAMETERS           ///
  ////////////////////////////////////////////////////

  /// @notice Reads the session ERC721 Token
  function readToken() public pure returns(address) {
    return _getArgAddress(0);
  }

  /// @notice Reads the Session Coordinator
  function readCoordinator() public pure returns(address) {
    return _getArgAddress(20);
  }

  /// @notice Reads the Session Allocation Period Start Timestamp
  function readAllocationStart() public pure returns(uint64) {
    return _getArgUint64(40);
  }

  /// @notice Reads the Session Allocation Period End Timestamp
  function readAllocationEnd() public pure returns(uint64) {
    return _getArgUint64(48);
  }

  /// @notice Reads the Session Minting Period Start Timestamp
  function readMintingStart() public pure returns(uint64) {
    return _getArgUint64(56);
  }

  /// @notice Reads the Session Minting Period End Timestamp
  function readMintingEnd() public pure returns(uint64) {
    return _getArgUint64(64);
  }

  /// @notice Reads the Session Minimum ERC721 Token Sale Price
  function readMinPrice() public pure returns(uint256) {
    return _getArgUint256(72);
  }

  /// @notice Reads the Session Maximum Number of Available Tokens to Mint
  function readMaxMintingAmount() public pure returns(uint256) {
    return _getArgUint256(104);
  }

  /// @notice Reads the Session Deposit ERC20 Token
  function readDepositToken() public pure returns(address) {
    return _getArgAddress(136);
  }

  /// @notice Reads the Session Rollover Option
  function readRolloverOption() public pure returns(uint8) {
    return _getArgUint8(156);
  }

  /// @notice Reads the Session ID
  function readSessionId() public pure returns(uint256) {
    return _getArgUint256(157);
  }

  /// @notice Reads the Twam Factory Address
  function readTwamFactoryAddress() public pure returns(address) {
    return _getArgAddress(189);
  }
}
