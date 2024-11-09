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
import './MerkleData.sol';

contract NukeFundTest is Test {
  address public owner;
  address public user1;
  NukeFund public nukeFund;
  TraitForgeNft public nft;
  DevFund public devFund;
  Airdrop public airdrop;
  EntityForging public entityForging;
  EntityTrading public entityTrading;
  EntropyGenerator public entropyGenerator;
  MerkleData public merkleData;

  bytes32 public rootHash;
  address[] public whitelistAddresses;
  mapping(address => bytes32) public leafNodes;
  mapping(address => bytes32[]) public proofs;

  function setUp() public {
    merkleData = new MerkleData();
    rootHash = merkleData.getRootHash();

    MerkleData.WhitelistEntry[] memory entries = merkleData
      .getWhitelistEntries();
    for (uint i = 0; i < entries.length; i++) {
      whitelistAddresses.push(entries[i].addr);
      leafNodes[entries[i].addr] = entries[i].leaf;
      proofs[entries[i].addr] = entries[i].proof;
    }

    owner = address(0x1);
    user1 = address(0x2);
    vm.startPrank(owner);

    // Deploy TraitForgeNft
    nft = new TraitForgeNft();

    // Deploy and setup DevFund
    devFund = new DevFund();
    devFund.addDev(owner, 1);

    // Deploy and setup Airdrop
    airdrop = new Airdrop();
    nft.setAirdropContract(address(airdrop));
    airdrop.transferOwnership(address(nft));

    // Deploy NukeFund
    nukeFund = new NukeFund(
      address(nft),
      address(airdrop),
      payable(devFund),
      payable(owner)
    );
    nft.setNukeFundContract(payable(address(nukeFund)));

    // Deploy and setup EntropyGenerator
    entropyGenerator = new EntropyGenerator(payable(address(nft)));
    entropyGenerator.writeEntropyBatch1();
    nft.setEntropyGenerator(address(entropyGenerator));

    // Deploy and setup EntityForging
    entityForging = new EntityForging(address(nft));
    nft.setEntityForgingContract(address(entityForging));

    // Setup MerkleTree
    merkleData = new MerkleData();
    nft.setRootHash(merkleData.getRootHash());

    // Deploy and setup EntityTrading
    entityTrading = new EntityTrading(address(nft));
    entityTrading.setNukeFundAddress(payable(nukeFund));

    // Mint token for owner
    bytes32[] memory proof = merkleData.getProofForAddress(owner);
    vm.deal(owner, 1 ether);
    nft.mintToken{ value: 1 ether }(proof);
    // Set minimumDaysHeld to 0 for testing purpose
    nukeFund.setMinimumDaysHeld(0);
    vm.stopPrank();
  }

  function test_merkle_root() public {
    console.logBytes32(rootHash);
  }

  function test_whitelist_entries() public {
    for (uint i = 0; i < whitelistAddresses.length; i++) {
      address addr = whitelistAddresses[i];
      console.log('Address:', addr);
      console.logBytes32(leafNodes[addr]);
      console.log('Proof length:', proofs[addr].length);
    }
  }

  function test_UpdateERC721ContractAddress() public {
    address newNftAddress = address(0x123);
    vm.prank(owner);
    // vm.expectEmit(true, false, false, true);
    // emit TraitForgeNftAddressUpdated(newNftAddress);
    nukeFund.setTraitForgeNftContract(newNftAddress);
    assertEq(address(nukeFund.nftContract()), newNftAddress);
  }

  // checks 10% of proceeds sent to nukeFund are distributed to dev fund
  // - if airdrop has not started
  function test_ReceiveFundsAndDistributeDevShare() public {
    // @note returns uint256 fund
    uint256 initialFundBalance = nukeFund.getFundBalance();
    uint256 devShare = 0.1 ether; // 10% of the sent amount
    uint256 initialDevBalance = address(nukeFund.devAddress()).balance;

    vm.prank(user1);
    vm.deal(user1, 1 ether);

    uint256 nukeFundBalanceBefore = address(nukeFund).balance;
    // receive() routes 10% to dev fund
    (bool success, ) = address(nukeFund).call{ value: 1 ether }('');
    require(success, 'Transaction failed');
    uint256 nukeFundBalanceAfter = address(nukeFund).balance;
    assertEq(nukeFundBalanceAfter - nukeFundBalanceBefore, 0.9 ether);

    // @note returns uint256 fund
    uint256 newFundBalance = nukeFund.getFundBalance();
    assertEq(newFundBalance, initialFundBalance + 0.9 ether);

    uint256 devBalance = address(nukeFund.devAddress()).balance;
    assertEq(devBalance, initialDevBalance + devShare);
  }

  function test_CalculateTokenAge() public {
    uint256 tokenId = 1;
    uint256 age = nukeFund.calculateAge(tokenId);
    assertEq(age, 0);
  }

  function test_NukeToken() public {
    uint256 tokenId = 1;

    // Mint a token
    vm.startPrank(owner);
    vm.deal(owner, 1 ether);
    bytes32[] memory proof = merkleData.getProofForAddress(owner);
    nft.mintToken{ value: 1 ether }(proof);
    vm.stopPrank();

    // Send some funds to the contract
    vm.prank(user1);
    vm.deal(user1, 1 ether);
    (bool success, ) = address(nukeFund).call{ value: 1 ether }('');
    require(success, 'Transaction failed');

    uint256 prevNukeFundBal = nukeFund.getFundBalance();

    // Ensure the token can be nuked
    // e- check if the token can be nuked by calculating the age of the token in seconds
    // - check if the token has been held for the minimum required days
    assertTrue(nukeFund.canTokenBeNuked(tokenId));

    uint256 prevUserEthBalance = address(owner).balance;

    vm.prank(owner);
    nft.approve(address(nukeFund), tokenId);

    // calculateNukeFactor determined off getTokenEntropy
    // higher entropy = higher nuke factor = higher claimable amount
    uint256 finalNukeFactor = nukeFund.calculateNukeFactor(tokenId);
    uint256 fund = nukeFund.getFundBalance();

    vm.prank(owner);
    nukeFund.nuke(tokenId);

    uint256 curUserEthBalance = address(owner).balance;
    uint256 curNukeFundBal = nukeFund.getFundBalance();

    assertTrue(curUserEthBalance > prevUserEthBalance);
    assertEq(nft.balanceOf(owner), 1);
    assertTrue(curNukeFundBal < prevNukeFundBal);
  }

  function test_LastTransferredTimestampUpdate() public {
    // Set minimum days held to 10 days in seconds
    vm.prank(owner);
    nukeFund.setMinimumDaysHeld(10 days);

    // Mint a new token
    vm.startPrank(owner);
    vm.deal(owner, 1 ether);
    bytes32[] memory proof = merkleData.getProofForAddress(owner);
    nft.mintToken{ value: 1 ether }(proof);
    vm.stopPrank();

    uint256 tokenId = 2; // Assuming this is the ID of the newly minted token

    // Fast forward 5 days
    vm.warp(block.timestamp + 5 days);
    assertFalse(nukeFund.canTokenBeNuked(tokenId));

    // Fast forward another 5 days (total 10 days)
    vm.warp(block.timestamp + 5 days);
    assertTrue(nukeFund.canTokenBeNuked(tokenId));

    // Transfer the token
    vm.prank(owner);
    nft.transferFrom(owner, user1, tokenId);

    // Check immediately after transfer
    assertFalse(nukeFund.canTokenBeNuked(tokenId));

    // Fast forward 10 days
    vm.warp(block.timestamp + 10 days);
    assertTrue(nukeFund.canTokenBeNuked(tokenId));
  }
}
