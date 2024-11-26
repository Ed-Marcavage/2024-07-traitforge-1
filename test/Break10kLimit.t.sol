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
import './NukeFund/MerkleData.sol';

contract Break10kLimit is Test {
  TraitForgeNft public nft;
  Airdrop public airdrop;
  EntropyGenerator public entropyGenerator;
  EntityForging public entityForging;
  DevFund public devFund;
  NukeFund public nukeFund;
  EntityTrading public entityTrading;
  MerkleData public merkleData;

  address public owner;
  address public user1;
  address public user2;

  function setUp() public {
    owner = address(0x1);
    user1 = address(0x2);
    user2 = address(0x3);

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

    vm.stopPrank();

    // Mint tokens for testing
    bytes32[] memory ownerProof = merkleData.getProofForAddress(owner);
    bytes32[] memory user1Proof = merkleData.getProofForAddress(user1);
    //bytes32[] memory user2Proof = merkleData.getProofForAddress(user2);

    vm.deal(owner, 100 ether);
    vm.deal(user1, 100 ether);
    vm.deal(user2, 100 ether);

    // vm.prank(user2);
    // nft.mintToken{ value: 1 ether }(user2Proof);
  }

  function test_MintWithBudgetAfter10k() public {
    // Skip time to end whitelist
    vm.warp(block.timestamp + 24 hours + 1);

    // Initial mints
    vm.startPrank(user1);
    nft.mintToken{ value: 1 ether }(new bytes32[](0));
    nft.mintToken{ value: 1 ether }(new bytes32[](0));
    nft.mintToken{ value: 1 ether }(new bytes32[](0));
    vm.stopPrank();

    // Verify entropy and forge potential for first tokens
    uint256 token1Entropy = nft.getTokenEntropy(2);
    uint256 token2Entropy = nft.getTokenEntropy(3);

    uint8 token1ForgePotential = uint8((token1Entropy / 10) % 10);
    uint8 token2ForgePotential = uint8((token2Entropy / 10) % 10);

    assertEq(token1ForgePotential, 5);

    bool isToken1Forger = token1Entropy % 3 == 0;
    bool isToken2Merger = token2Entropy % 3 != 0;

    assertTrue(isToken1Forger);
    assertTrue(isToken2Merger);

    // Transfer token 2 to user2
    vm.prank(user1);
    nft.transferFrom(user1, user2, 2);

    assertEq(nft.ownerOf(1), user1);
    assertEq(nft.ownerOf(2), user2);

    // Mint remaining tokens to reach 10k
    vm.startPrank(user2);
    for (uint256 i = 0; i < 9998; i++) {
      nft.mintToken{ value: 1 ether }(new bytes32[](0));
    }
    vm.stopPrank();

    // Verify generation state
    assertEq(nft.getGeneration(), 1);
    assertEq(nft.getTokenGeneration(10_000), 1);

    // Test forging
    vm.prank(user1);
    entityForging.listForForging(1, 0.01 ether);

    vm.prank(user2);
    entityForging.forgeWithListed{ value: 0.01 ether }(1, 2);

    // Verify forged token generation
    assertEq(nft.getTokenGeneration(10_001), 2);
    assertEq(nft.generationMintCounts(2), 1);

    // Mint one more token
    vm.prank(user1);
    nft.mintToken{ value: 1 ether }(new bytes32[](0));

    // Final verifications
    assertEq(nft.generationMintCounts(2), 1);
    assertEq(nft.getTokenGeneration(10_002), 2);

    // Verify non-existence of token 10_003
    vm.expectRevert('ERC721: invalid token ID');
    nft.ownerOf(10_003);
  }
}
