// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Test.sol';
import { Test, console } from 'forge-std/Test.sol';
import '../../contracts/NukeFund/NukeFund.sol';
import '../../contracts/TraitForgeNft/TraitForgeNft.sol';
import '../../contracts/DevFund/DevFund.sol';
import '../../contracts/Airdrop/Airdrop.sol';
import '../../contracts/EntityForging/EntityForging.sol';
import '../../contracts/EntityTrading/EntityTrading.sol';
import '../../contracts/EntropyGenerator/EntropyGenerator.sol';
import '../NukeFund/MerkleData.sol';

contract EntityForgingTest is Test {
  EntityForging public entityForging;
  TraitForgeNft public nft;
  address public owner;
  address public user1;
  address public user2;
  address public user3;
  EntityTrading public entityTrading;
  NukeFund public nukeFund;
  DevFund public devFund;
  Airdrop public airdrop;
  EntropyGenerator public entropyGenerator;
  MerkleData public merkleData;
  uint256 public FORGER_TOKEN_ID;
  uint256 public MERGER_TOKEN_ID;

  uint256 constant FORGING_FEE = 1 ether;

  function setUp() public {
    owner = address(0x1);
    user1 = address(0x2);
    user2 = address(0x3);
    user3 = address(0x4);

    vm.startPrank(owner);

    // Deploy TraitForgeNft
    nft = new TraitForgeNft();

    // Deploy and setup Airdrop
    airdrop = new Airdrop();
    nft.setAirdropContract(address(airdrop));
    airdrop.transferOwnership(address(nft));

    // Deploy and setup EntropyGenerator
    entropyGenerator = new EntropyGenerator(address(nft));
    entropyGenerator.writeEntropyBatch1();
    nft.setEntropyGenerator(address(entropyGenerator));

    // Deploy EntityForging
    entityForging = new EntityForging(address(nft));
    nft.setEntityForgingContract(address(entityForging));

    // Deploy DevFund
    devFund = new DevFund();

    // Deploy NukeFund
    nukeFund = new NukeFund(
      address(nft),
      address(airdrop),
      payable(devFund),
      payable(owner)
    );
    nft.setNukeFundContract(payable(address(nukeFund)));

    // Deploy EntityTrading
    entityTrading = new EntityTrading(address(nft));
    entityTrading.setNukeFundAddress(payable(nukeFund));

    // Setup MerkleTree
    merkleData = new MerkleData();
    nft.setRootHash(merkleData.getRootHash());

    // Mint tokens for testing
    bytes32[] memory ownerProof = merkleData.getProofForAddress(owner);
    bytes32[] memory user1Proof = merkleData.getProofForAddress(user1);

    vm.deal(owner, 100 ether);
    vm.deal(user1, 100 ether);

    nft.mintToken{ value: 1 ether }(ownerProof);

    vm.stopPrank();

    vm.prank(user1);
    nft.mintToken{ value: 1 ether }(user1Proof);

    vm.prank(user1);
    nft.mintToken{ value: 1 ether }(user1Proof);

    vm.startPrank(owner);
    for (uint256 i = 0; i < 10; i++) {
      nft.mintToken{ value: 1 ether }(ownerProof);
      bool isForger = nft.isForger(i + 4);
      if (isForger) {
        FORGER_TOKEN_ID = i + 4;
        break;
      }
    }

    MERGER_TOKEN_ID = 3;

    vm.stopPrank();

    console.log('Is FORGER_TOKEN_ID a forger:', nft.isForger(FORGER_TOKEN_ID));
    console.log('Is MERGER_TOKEN_ID a forger:', nft.isForger(MERGER_TOKEN_ID));
    console.log(
      'Forging count for FORGER_TOKEN_ID:',
      entityForging.forgingCounts(FORGER_TOKEN_ID)
    );
    console.log(
      'Entropy for FORGER_TOKEN_ID:',
      nft.getTokenEntropy(FORGER_TOKEN_ID)
    );
  }

  function testCannotListForForgingByNonOwner() public {
    uint256 tokenId = 1;
    uint256 fee = FORGING_FEE;

    vm.prank(user1);
    vm.expectRevert('Caller must own the token');
    entityForging.listForForging(tokenId, fee);
  }

  // adds token to listings mappings
  function testCanListForForgingByOwner() public {
    uint256 tokenId = FORGER_TOKEN_ID;
    uint256 fee = FORGING_FEE;

    vm.prank(owner);
    entityForging.listForForging(tokenId, fee);

    uint256 listedTokenId = entityForging.listedTokenIds(tokenId);
    (, , bool isListed, uint256 listedFee) = entityForging.listings(
      listedTokenId
    );

    assertTrue(isListed, 'Token should be listed');
    assertEq(listedFee, fee, 'Listed fee should match the set fee');
  }

  function testCannotForgeWithUnlistedForgerToken() public {
    uint256 forgerTokenId = MERGER_TOKEN_ID;
    uint256 mergerTokenId = FORGER_TOKEN_ID;

    vm.prank(user1);
    vm.expectRevert("Forger's entity not listed for forging");
    entityForging.forgeWithListed{ value: FORGING_FEE }(
      forgerTokenId,
      mergerTokenId
    );

    // Additional assertions as needed
  }

  // @todo - return here once you unit test traitFoge to get idea how
  // how ot join the games
  function testForgeWithListedToken() public {
    uint256 forgerTokenId = FORGER_TOKEN_ID;
    uint256 mergerTokenId = MERGER_TOKEN_ID;

    // List the forger token for forging
    vm.startPrank(owner);
    entityForging.listForForging(forgerTokenId, FORGING_FEE);
    vm.stopPrank();

    // // Ensure user1 owns the merger token
    // if (nft.ownerOf(mergerTokenId) != user1) {
    //   vm.prank(nft.ownerOf(mergerTokenId));
    //   nft.transferFrom(nft.ownerOf(mergerTokenId), user1, mergerTokenId);
    // }

    uint256 initialBalance = owner.balance;

    uint256 forgerEntropy = nft.getTokenEntropy(forgerTokenId);
    uint256 mergerEntropy = nft.getTokenEntropy(mergerTokenId);
    uint256 expectedTokenId = nft.totalSupply() + 1;

    vm.startPrank(user1);
    entityForging.forgeWithListed{ value: FORGING_FEE }(
      forgerTokenId,
      mergerTokenId
    );
    vm.stopPrank();

    uint256 finalBalance = owner.balance;

    assertEq(
      finalBalance - initialBalance,
      (FORGING_FEE * 9) / 10,
      'Incorrect balance change'
    );

    // Check forger nft delisted
    (, , bool isListed, ) = entityForging.listings(forgerTokenId);
    assertFalse(isListed, 'Forger token should be delisted');

    // Check the new token was minted
    assertEq(
      nft.ownerOf(expectedTokenId),
      user1,
      'New token should be owned by user1'
    );

    // Check the entropy of the new token
    uint256 newTokenEntropy = nft.getTokenEntropy(expectedTokenId);
    assertEq(
      newTokenEntropy,
      (forgerEntropy + mergerEntropy) / 2,
      'New token entropy should be average of parent entropies'
    );
  }
}
