// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, StdInvariant, console2 } from 'forge-std/Test.sol';
import '../../contracts/EntityTrading/EntityTrading.sol';
import '../../contracts/TraitForgeNft/TraitForgeNft.sol';
import '../../contracts/NukeFund/NukeFund.sol';
import '../../contracts/EntityForging/EntityForging.sol';
import '../../contracts/EntropyGenerator/EntropyGenerator.sol';
import '../NukeFund/MerkleData.sol';

// import { ThePredicter } from '../../src/ThePredicter.sol';
// import { ScoreBoard } from '../../src/ScoreBoard.sol';

contract IntegrationHandler is Test {
  uint256[] public allTokenIds;
  mapping(uint256 => TokenInfo) public tokenInfo;
  struct TokenInfo {
    bool exists;
    bool isForger;
    bool isListed;
    bool isListedForForging;
    bool isPurchased;
    bool isNuked;
  }
  uint256[] public forgerTokenIds;
  uint256[] public mergerTokenIds;

  EntityForging public entityForging;
  EntityTrading public entityTrading;
  TraitForgeNft public nft;
  EntropyGenerator public entropyGenerator;

  address public owner;
  address public buyer;
  NukeFund public nukeFund;

  uint256 public token_id = 1; //487800 413400
  uint256 public constant LISTING_PRICE = 1 ether;
  uint256 constant FORGING_FEE = 1 ether;

  // array of post purchased NFts IDs
  uint256[] public purchasedTokenIds;

  uint256[] public enteredTokenIds;
  // Forging Merging tracking
  uint256[] public ListedForForgingTokenIds;
  // track how many times the NFT has been listed

  MerkleData public merkleData;
  bytes32[] public proof;
  // track total mints

  // Ghost Variables
  uint256 public buyingCount = 0;
  uint256 public mergedCount = 0;
  uint256 public cancelListingCounts = 0;
  uint256 public claimAmount = 0;
  uint256 public totalMints = 0;

  constructor(
    EntityTrading _entityTrading,
    TraitForgeNft _nft,
    address _owner,
    address _buyer,
    NukeFund _nukeFund,
    MerkleData _merkleData,
    EntityForging _entityForging,
    EntropyGenerator _entropyGenerator
  ) {
    entityTrading = _entityTrading;
    nft = _nft;

    owner = _owner;
    buyer = _buyer;
    nukeFund = _nukeFund;
    merkleData = _merkleData;
    entityForging = _entityForging;
    entropyGenerator = _entropyGenerator;

    proof = merkleData.getProofForAddress(owner);

    // Initialize entropy multiple time

    vm.startPrank(owner);
    vm.deal(owner, 100 ether);
    bytes32[] memory ownerProof = merkleData.getProofForAddress(owner);

    for (uint i = 0; i < 100; i++) {
      nft.mintToken{ value: 0.1 ether }(ownerProof);

      bool isForger = nft.isForger(token_id);
      addToken(token_id, isForger);
      totalMints++;

      token_id++;
    }

    // Optionally, call initializeAlphaIndices again to potentially change the special case
    // if (i % 3 == 0) {
    //   entropyGenerator.initializeAlphaIndices();
    //   // }
    // }

    vm.stopPrank();
  }

  function ListNFTForForging(uint256 TokenIdSeed) public {
    if (forgerTokenIds.length == 0) {
      console2.log('No forger tokens available');
      return;
    }

    uint256 tokenId = forgerTokenIds[TokenIdSeed % forgerTokenIds.length];

    if (
      tokenInfo[tokenId].isListedForForging ||
      tokenInfo[tokenId].isListed ||
      !tokenInfo[tokenId].exists ||
      !tokenInfo[tokenId].isForger ||
      tokenInfo[tokenId].isNuked
    ) {
      return;
    }

    uint256 entropy = nft.getTokenEntropy(tokenId);
    uint8 forgePotential = uint8((entropy / 10) % 10);
    if (
      forgePotential == 0 ||
      entityForging.forgingCounts(tokenId) > forgePotential
    ) {
      console2.log(
        'Token',
        entropy,
        'has insufficient forge potential or has reached its forging limit'
      );
      return;
    }

    if (nft.ownerOf(tokenId) != owner) {
      vm.startPrank(buyer);
      nft.transferFrom(nft.ownerOf(tokenId), owner, tokenId);
      vm.stopPrank();
    }

    vm.startPrank(owner);
    entityForging.listForForging(tokenId, FORGING_FEE);
    vm.stopPrank();

    listForForging(tokenId);
  }

  function mergeWithListedToken(uint96 TokenIdSeed) public {
    if (forgerTokenIds.length == 0 || mergerTokenIds.length == 0) {
      console2.log('Not enough tokens of each type to merge');
      return;
    }

    uint256 mergerTokenId = mergerTokenIds[TokenIdSeed % mergerTokenIds.length];
    uint256 forgerTokenId = forgerTokenIds[TokenIdSeed % forgerTokenIds.length];

    if (
      tokenInfo[mergerTokenId].isNuked ||
      !tokenInfo[forgerTokenId].isListedForForging ||
      tokenInfo[mergerTokenId].isListed
    ) {
      console2.log('One or both tokens are not in a valid state for merging');
      return;
    }

    if (nft.ownerOf(mergerTokenId) != buyer) {
      vm.startPrank(owner);
      nft.transferFrom(nft.ownerOf(mergerTokenId), buyer, mergerTokenId);
      vm.stopPrank();
    }

    uint256 mergerEntropy = nft.getTokenEntropy(mergerTokenId);
    uint8 mergerForgePotential = uint8((mergerEntropy / 10) % 10);
    uint256 forgingCount = entityForging.forgingCounts(mergerTokenId);

    // console2.log('mergerTokenId:', mergerTokenId);
    // console2.log('mergerEntropy:', mergerEntropy);
    // console2.log('mergerForgePotential:', mergerForgePotential);
    // console2.log('forgingCount:', forgingCount);

    if (mergerForgePotential == 0 || forgingCount >= mergerForgePotential) {
      console2.log(
        'Token has insufficient forge potential or has reached its forging limit'
      );
      return;
    }

    if (
      nft.getTokenGeneration(mergerTokenId) !=
      nft.getTokenGeneration(forgerTokenId)
    ) {
      console2.log('Tokens are not of the same generation');
      return;
    }

    vm.startPrank(buyer);
    vm.deal(buyer, FORGING_FEE);
    uint256 newTokenId = entityForging.forgeWithListed{ value: FORGING_FEE }(
      forgerTokenId,
      mergerTokenId
    );
    vm.stopPrank();

    tokenInfo[forgerTokenId].isListedForForging = false;

    // Add the new forged token
    addToken(newTokenId, nft.isForger(newTokenId));
    mergedCount++;
  }

  function ListNFTForSale(uint256 randomSeed) public {
    if (allTokenIds.length == 0) {
      return;
    }

    uint256 tokenId = allTokenIds[randomSeed % allTokenIds.length];

    if (
      tokenInfo[tokenId].isListedForForging ||
      tokenInfo[tokenId].isListed ||
      !tokenInfo[tokenId].exists ||
      tokenInfo[tokenId].isNuked
    ) {
      return;
    }

    address currentOwner = nft.ownerOf(tokenId);
    if (currentOwner != owner) {
      vm.startPrank(currentOwner);
      nft.transferFrom(currentOwner, owner, tokenId);
      vm.stopPrank();
    }

    vm.startPrank(owner);
    nft.approve(address(entityTrading), tokenId);

    entityTrading.listNFTForSale(tokenId, LISTING_PRICE);
    tokenInfo[tokenId].isListed = true;

    uint256 listingId = entityTrading.listedTokenIds(tokenId);
    (
      address account,
      uint256 tempTokenId,
      uint256 price,
      bool isListed
    ) = entityTrading.listings(listingId);

    vm.stopPrank();

    assertEq(account, owner);
    assertEq(tokenId, tempTokenId);
    assertEq(price, LISTING_PRICE);
    assertTrue(isListed);

    vm.stopPrank();
  }

  function buyNFT(uint256 randomSeed) public {
    if (allTokenIds.length == 0) {
      return;
    }

    uint256 tokenId = allTokenIds[randomSeed % allTokenIds.length];

    if (!tokenInfo[tokenId].isListed) {
      return;
    }

    vm.deal(buyer, buyer.balance + LISTING_PRICE);

    //console2.log('Listing count', entityTrading.listingCount());

    uint256 listingId = entityTrading.listedTokenIds(tokenId);

    vm.startPrank(buyer);
    entityTrading.buyNFT{ value: LISTING_PRICE }(tokenId);
    tokenInfo[tokenId].isListed = false;
    buyingCount++;
    vm.stopPrank();

    (
      address account,
      uint256 tempTokenId,
      uint256 price,
      bool isListed
    ) = entityTrading.listings(listingId);

    assertEq(nft.ownerOf(tokenId), buyer);
    assertEq(account, address(0));
    assertEq(tempTokenId, 0);
    assertEq(price, 0);
    assertFalse(isListed);
  }

  function cancelListing(uint256 randomSeed) public {
    if (allTokenIds.length == 0) {
      return;
    }

    uint256 tokenId = allTokenIds[randomSeed % allTokenIds.length];

    if (!tokenInfo[tokenId].isListed || tokenInfo[tokenId].isNuked) {
      return;
    }

    vm.startPrank(owner);

    // Check that the NFT is owned by the contract before cancellation
    assertEq(nft.ownerOf(tokenId), address(entityTrading));

    // Cancel the listing
    entityTrading.cancelListing(tokenId);
    cancelListingCounts++;
    tokenInfo[tokenId].isListed = false;

    // Check that the NFT is returned to the owner
    assertEq(nft.ownerOf(tokenId), owner);

    // Check that the listing is removed
    uint256 listingId = entityTrading.listedTokenIds(tokenId);
    (
      address account,
      uint256 tempTokenId,
      uint256 price,
      bool isListed
    ) = entityTrading.listings(listingId);

    assertEq(account, address(0), 'Listing account should be zero address');
    assertEq(tempTokenId, 0, 'Listing token ID should be zero');
    assertEq(price, 0, 'Listing price should be zero');
    assertFalse(isListed, 'Listing should not be active');

    vm.stopPrank();
  }

  function nukeToken(uint256 randomSeed) public {
    if (allTokenIds.length == 0) {
      return;
    }
    uint256 tokenId = allTokenIds[randomSeed % allTokenIds.length];

    if (tokenInfo[tokenId].isNuked) {
      return;
    }
    // uint256 listingId = entityTrading.listedTokenIds(tokenId);

    claimAmount += trackNukes(tokenId);

    address currentOwner = nft.ownerOf(tokenId);

    // If the current owner is neither buyer nor owner, we need to transfer it first
    if (currentOwner != buyer && currentOwner != owner) {
      vm.startPrank(currentOwner);
      nft.transferFrom(currentOwner, buyer, tokenId);
      vm.stopPrank();
      currentOwner = buyer;
    }

    vm.startPrank(currentOwner);
    nft.approve(address(nukeFund), tokenId);
    nukeFund.nuke(tokenId);
    tokenInfo[tokenId].isNuked = true;
    vm.stopPrank();
  }

  function trackNukes(
    uint256 tokenId
  ) public view returns (uint256 claimAmount) {
    uint256 finalNukeFactor = nukeFund.calculateNukeFactor(tokenId);
    uint256 potentialClaimAmount = (nukeFund.getFundBalance() *
      finalNukeFactor) / nukeFund.MAX_DENOMINATOR();

    uint256 maxAllowedClaimAmount = nukeFund.getFundBalance() /
      nukeFund.maxAllowedClaimDivisor();

    claimAmount = finalNukeFactor > nukeFund.nukeFactorMaxParam()
      ? maxAllowedClaimAmount
      : potentialClaimAmount;
  }

  // Invariant Helper Functions
  function addToken(uint256 tokenId, bool isForger) internal {
    if (tokenInfo[tokenId].exists) return;
    tokenInfo[tokenId] = TokenInfo(true, isForger, false, false, false, false);
    allTokenIds.push(tokenId);
    if (isForger) {
      forgerTokenIds.push(tokenId);
    } else {
      mergerTokenIds.push(tokenId);
    }
  }

  function listForForging(uint256 tokenId) internal {
    tokenInfo[tokenId].isListedForForging = true;
  }
}
