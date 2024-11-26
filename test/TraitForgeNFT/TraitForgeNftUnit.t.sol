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

contract TraitForgeNFTTest is Test {
  uint256 public FORGER_TOKEN_ID;
  uint256 public MERGER_TOKEN_ID;
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

  bytes32[] public ownerProof;
  bytes32[] public user1Proof;

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
    ownerProof = merkleData.getProofForAddress(owner);
    user1Proof = merkleData.getProofForAddress(user1);
    //bytes32[] memory user2Proof = merkleData.getProofForAddress(user2);

    vm.deal(owner, 100 ether);
    vm.deal(user1, 100 ether);
    vm.deal(user2, 100 ether);

    // vm.prank(user2);
    // nft.mintToken{ value: 1 ether }(user2Proof);
  }

  // Your test functions will go here
  function testWhitelistedAddressesMinting() public {
    bytes32[] memory ownerProof = merkleData.getProofForAddress(owner);
    bytes32[] memory user1Proof = merkleData.getProofForAddress(user1);
    // Owner mints a token
    vm.startPrank(owner);
    nft.mintToken{ value: 1 ether }(ownerProof);
    console.log('isForger 1', nft.isForger(nft.totalSupply()));
    nft.mintToken{ value: 1 ether }(ownerProof);
    console.log('isForger 2', nft.isForger(nft.totalSupply()));
    vm.stopPrank();

    // User1 mints two tokens
    vm.startPrank(user1);
    nft.mintToken{ value: 1 ether }(user1Proof);
    console.log('isForger 3', nft.isForger(nft.totalSupply()));
    nft.mintToken{ value: 1 ether }(user1Proof);
    console.log('isForger 4', nft.isForger(nft.totalSupply()));
    nft.mintToken{ value: 1 ether }(user1Proof);
    console.log('isForger 5', nft.isForger(nft.totalSupply()));
    vm.stopPrank();

    // Check balances
    assertEq(nft.balanceOf(owner), 2, 'Owner should have 2 tokens'); // Note: 2 because one was minted in setUp
    assertEq(nft.balanceOf(user1), 3, 'User1 should have 3 tokens'); // Note: 3 because one was minted in setUp
  }

  function testIncorrectAccessControls() public {
    vm.pauseGasMetering();
    // call mintToken 10,001 times
    vm.startPrank(owner);
    // uint256 public maxTokensPerGen = 10000
    for (uint i = 0; i < 10001; i++) {
      vm.deal(owner, 1 ether);
      nft.mintToken{ value: 1 ether }(ownerProof);
    }
    vm.stopPrank();
  }

  function testMaxSupplyLimit() public {
    vm.pauseGasMetering();

    // Get a forger and merger token
    (uint256 token1, uint256 token2) = getTestTokens();

    uint256 token1Entropy = nft.getTokenEntropy(token1);
    uint256 token2Entropy = nft.getTokenEntropy(token2);

    // Calculate forge potential
    uint8 token1ForgePotential = uint8((token1Entropy / 10) % 10);

    assertGt(
      token1ForgePotential,
      0,
      'Token 1 forge potential should be greater than 0'
    );

    // Check if tokens are forger/merger
    bool isToken1Forger = token1Entropy % 3 == 0;
    bool isToken2Merger = token2Entropy % 3 != 0;

    assertTrue(isToken1Forger, 'Token 1 should be a forger');
    assertTrue(isToken2Merger, 'Token 2 should be a merger');

    vm.deal(owner, 20000 ether);
    vm.startPrank(owner);

    console.log('Total supply before minting: ', nft.totalSupply());
    console.log('Generation before minting: ', nft.getGeneration());
    console.log(
      'Token generation mint counts before minting: ',
      nft.generationMintCounts(1)
    );
    console.log('---------------------------------------------------');
    uint256 maxTokens = 10000 - (nft.totalSupply());
    for (uint i = 0; i < maxTokens; i++) {
      nft.mintToken{ value: 1 ether }(ownerProof);
    }
    console.log('Total supply after minting: ', nft.totalSupply());
    console.log('Generation after minting: ', nft.getGeneration());
    console.log(
      'Token generation mint counts after minting & before forging (1): ',
      nft.generationMintCounts(1)
    );
    console.log('---------------------------------------------------');
    // Verify we're at generation 1
    assertEq(nft.getGeneration(), 1);
    assertEq(nft.getTokenGeneration(10_000), 1);

    // Forge a new token (creates token 10_001 in generation 2)
    vm.startPrank(owner);
    entityForging.listForForging(token1, 0.01 ether);
    nft.transferFrom(owner, user1, token2);
    vm.stopPrank();
    vm.startPrank(user1);
    //forgeWithListed -> forge -> _mintNewEntity -> _incrementGeneration ->  generationMintCounts[currentGeneration] = 0;
    entityForging.forgeWithListed{ value: 0.01 ether }(token1, token2);
    vm.stopPrank();
    console.log('Total supply after forging: ', nft.totalSupply());
    // q - whys currentGeneration not 2 after forging?
    // a -  generationMintCounts[gen] >= maxTokensPerGen isnt tiggered in _mintNewEntity bc generationMintCounts[2] is 1 not 10k, so currentGeneration isnt updated
    console.log('Generation after forging: ', nft.getGeneration());
    console.log(
      'Token generation mint counts after forging (1): ',
      nft.generationMintCounts(1)
    );
    console.log(
      'Token generation mint counts after forging (2): ',
      nft.generationMintCounts(2)
    );
    console.log('---------------------------------------------------');

    // Verify the forged token is generation 2
    // based on this q // q - whys currentGeneration not 2 after forging?
    // why is this correctly 2? - because mapping is directly updated in _mintNewEntity
    assertEq(nft.getTokenGeneration(10_001), 2);
    assertEq(nft.generationMintCounts(2), 1);

    // Mint one more token after forging
    // State brain dump here

    // totalSupply is 10_001
    // generationMintCounts[1] is 10k
    // generationMintCounts[2] is 1
    // currentGeneration is 1 (should this be max, thus 2?)

    vm.startPrank(user1);
    nft.mintToken{ value: 1 ether }(user1Proof);
    vm.stopPrank();
    console.log('Total supply after second minting: ', nft.totalSupply());
    // correctly set to 2 here because mint() calls _incrementGeneration
    console.log('Generation after second minting: ', nft.getGeneration());
    console.log(
      'Token generation mint counts after second minting (2) - this should be 2: ',
      nft.generationMintCounts(2)
    );
    console.log('---------------------------------------------------');

    // Check generation mint count hasn't changed
    uint256 generation2MintCountAfterIncrementingGeneration = nft
      .generationMintCounts(2);

    assertEq(
      generation2MintCountAfterIncrementingGeneration,
      1,
      'Generation 2 mint count should still be 1'
    );

    // Check generation of the newly minted token
    uint256 generationOfFirstGeneration2TokenByMint = nft.getTokenGeneration(
      10_002
    );
    assertEq(
      generationOfFirstGeneration2TokenByMint,
      2,
      'New token should be generation 2'
    );

    // Verify that token 10_003 doesn't exist
    vm.expectRevert('ERC721: invalid token ID');
    nft.ownerOf(10_003);
  }

  function test_NonWhitelistedAddressMinting() public {
    vm.startPrank(user2);
    vm.expectRevert('Not whitelisted user');
    nft.mintToken{ value: 1 ether }(user1Proof);
    vm.stopPrank();
  }

  function getTestTokens()
    public
    returns (uint256 forgerTokenId, uint256 mergerTokenId)
  {
    vm.startPrank(owner);
    uint256 currentTokenId = nft.totalSupply();

    for (uint i = 0; i < 10000; i++) {
      nft.mintToken{ value: 1 ether }(ownerProof);
      uint256 tokenId = currentTokenId + i;
      if (tokenId == 0) continue;

      uint256 entropy = nft.getTokenEntropy(tokenId);
      uint8 forgePotential = uint8((entropy / 10) % 10);
      bool isForger = nft.isForger(tokenId);

      // If we haven't found a forger yet and this is one with potential
      if (forgerTokenId == 0 && isForger && forgePotential > 0) {
        forgerTokenId = tokenId;
      }
      // If we haven't found a merger yet and this is one
      if (mergerTokenId == 0 && !isForger) {
        mergerTokenId = tokenId;
      }
      // Exit if we found both
      if (forgerTokenId != 0 && mergerTokenId != 0) break;
    }
    vm.stopPrank();
    return (forgerTokenId, mergerTokenId);
  }

  // function test_ForgerTokenExists() public {
  //   FORGER_TOKEN_ID = getForgerToken();
  //   console.log('Forger token ID: ', FORGER_TOKEN_ID);
  //   assertTrue(FORGER_TOKEN_ID != 0, 'Forger token ID should not be 0');
  // }

  // @todo dont test this for now
  //   function testNonWhitelistedAddressMintingAfter24Hours() public {
  //     bytes32[] memory user2Proof = merkleData.getProofForAddress(user2);

  //     // Fast forward time by 24 hours + 1 second
  //     vm.warp(block.timestamp + 24 hours + 1 seconds);

  //     vm.prank(user2);
  //     nft.mintToken{ value: 1 ether }(user2Proof);
  //     nft.mintToken{ value: 1 ether }(user2Proof);

  //     assertEq(nft.balanceOf(user2), 2, 'User2 should have 2 tokens'); // Note: 2 because one was minted in setUp
  //   }
}
