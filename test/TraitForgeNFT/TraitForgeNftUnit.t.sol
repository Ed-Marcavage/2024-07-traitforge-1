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
    bytes32[] memory ownerProof = merkleData.getProofForAddress(owner);
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
    bytes32[] memory ownerProof = merkleData.getProofForAddress(owner);

    vm.deal(owner, 20000 ether);
    vm.startPrank(owner);

    // Try to mint one more than the max
    uint256 maxTokens = 10001;
    for (uint i = 0; i <= maxTokens; i++) {
      nft.mintToken{ value: 1 ether }(ownerProof);
    }

    vm.stopPrank();
  }

  function test_NonWhitelistedAddressMinting() public {
    bytes32[] memory user1Proof = merkleData.getProofForAddress(user1);

    vm.startPrank(user2);
    vm.expectRevert('Not whitelisted user');
    nft.mintToken{ value: 1 ether }(user1Proof);
    vm.stopPrank();
  }

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
