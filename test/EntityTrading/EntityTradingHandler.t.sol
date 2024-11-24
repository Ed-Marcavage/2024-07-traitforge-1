// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, StdInvariant, console2 } from 'forge-std/Test.sol';
import '../../contracts/EntityTrading/EntityTrading.sol';
import '../../contracts/test/TestERC721.sol';

// import { ThePredicter } from '../../src/ThePredicter.sol';
// import { ScoreBoard } from '../../src/ScoreBoard.sol';

contract EntityTradingHandler is Test {
  EntityTrading public entityTrading;
  TestERC721 public nft;

  address public owner;
  address public buyer;
  address public nukeFund;

  uint256 public token_id = 0;
  uint256 public constant LISTING_PRICE = 1 ether;

  // array of post purchased NFts IDs
  uint256[] public listedTokenIds;
  // track how many times the NFT has been listed
  uint256 public buyingCount = 0;

  constructor(
    EntityTrading _entityTrading,
    TestERC721 _nft,
    address _owner,
    address _buyer,
    address _nukeFund
  ) {
    entityTrading = _entityTrading;
    nft = _nft;

    owner = _owner;
    buyer = _buyer;
    nukeFund = _nukeFund;
  }

  function ListNFTForSale() public {
    vm.startPrank(owner);
    nft.mintToken(owner);
    nft.approve(address(entityTrading), token_id);

    entityTrading.listNFTForSale(token_id, LISTING_PRICE);
    console2.log('Listed NFT for sale', entityTrading.listedTokenIds(token_id));

    uint256 listingId = entityTrading.listedTokenIds(token_id);
    (
      address account,
      uint256 tokenId,
      uint256 price,
      bool isListed
    ) = entityTrading.listings(listingId);

    assertEq(account, owner);
    assertEq(token_id, tokenId);
    assertEq(price, LISTING_PRICE);
    assertTrue(isListed);

    listedTokenIds.push(token_id);
    token_id++;

    vm.stopPrank();
  }

  function buyNFT(uint256 randomSeed) public {
    if (listedTokenIds.length == 0) {
      return;
    }
    vm.deal(buyer, LISTING_PRICE);

    uint256 tokenId = listedTokenIds[randomSeed % listedTokenIds.length];

    console2.log('Buying NFT', tokenId);
    //console2.log('Listing count', entityTrading.listingCount());

    uint256 listingId = entityTrading.listedTokenIds(tokenId);

    vm.startPrank(buyer);
    entityTrading.buyNFT{ value: LISTING_PRICE }(tokenId);
    buyingCount++;
    vm.stopPrank();

    // Remove the purchased token ID from the listedTokenIds array
    for (uint256 i = 0; i < listedTokenIds.length; i++) {
      if (listedTokenIds[i] == tokenId) {
        listedTokenIds[i] = listedTokenIds[listedTokenIds.length - 1];
        listedTokenIds.pop();
        break;
      }
    }

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
    if (listedTokenIds.length == 0) {
      return;
    }
    uint256 tokenId = listedTokenIds[randomSeed % listedTokenIds.length];

    vm.startPrank(owner);

    // Check that the NFT is owned by the contract before cancellation
    assertEq(nft.ownerOf(tokenId), address(entityTrading));

    // Cancel the listing
    entityTrading.cancelListing(tokenId);

    // Check that the NFT is returned to the owner
    assertEq(nft.ownerOf(tokenId), owner);

    for (uint256 i = 0; i < listedTokenIds.length; i++) {
      if (listedTokenIds[i] == tokenId) {
        listedTokenIds[i] = listedTokenIds[listedTokenIds.length - 1];
        listedTokenIds.pop();
        break;
      }
    }

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
}
