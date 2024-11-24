// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Test.sol';
import '../../contracts/EntityTrading/EntityTrading.sol';
import '../../contracts/test/TestERC721.sol';
import { Test, console } from 'forge-std/Test.sol';

contract EntityTradingTest is Test {
  EntityTrading public entityTrading;
  TestERC721 public nft;

  address public owner;
  address public buyer;
  address public nukeFund;

  uint256 constant TOKEN_ID = 0;
  uint256 constant LISTING_PRICE = 1 ether;

  struct Listing {
    address account;
    uint256 tokenId;
    bool isListed;
    uint256 fee;
  }

  // ----- Summary ------
  // List NFT for sale
  // Buy NFT
  // Cancel listing
  // Nuke fund

  function setUp() public {
    owner = address(0x3);
    buyer = address(0x1);
    nukeFund = address(0x2);

    vm.startPrank(owner);
    nft = new TestERC721();

    entityTrading = new EntityTrading(address(nft));
    entityTrading.setNukeFundAddress(payable(nukeFund));
    vm.stopPrank();
  }

  function testListNFTForSale() public {
    console.log('buyer', buyer);
    console.log('nukeFund', nukeFund);
    nft.mintToken(owner);
    vm.startPrank(owner);
    nft.approve(address(entityTrading), TOKEN_ID);

    entityTrading.listNFTForSale(TOKEN_ID, LISTING_PRICE);

    uint256 listingId = entityTrading.listedTokenIds(TOKEN_ID);
    (
      address account,
      uint256 tokenId,
      uint256 price,
      bool isListed
    ) = entityTrading.listings(listingId);

    vm.stopPrank();

    assertEq(account, owner);
    assertEq(tokenId, TOKEN_ID);
    assertEq(price, LISTING_PRICE);
    assertTrue(isListed);
  }

  function test_buyNFT() public listNft {
    vm.deal(buyer, LISTING_PRICE);
    // vm.deal(address(entityTrading), LISTING_PRICE); // @audit - remove this line

    vm.startPrank(buyer);
    console.log('b4', address(entityTrading).balance);
    entityTrading.buyNFT{ value: LISTING_PRICE }(TOKEN_ID);
    console.log('after', address(entityTrading).balance);
    vm.stopPrank();

    assertEq(nft.ownerOf(TOKEN_ID), buyer);
  }

  function testCancelListing() public listNft {
    vm.startPrank(owner);

    // Check that the NFT is owned by the contract before cancellation
    assertEq(nft.ownerOf(TOKEN_ID), address(entityTrading));

    // Cancel the listing
    entityTrading.cancelListing(TOKEN_ID);

    // Check that the NFT is returned to the owner
    assertEq(nft.ownerOf(TOKEN_ID), owner);

    // Check that the listing is removed
    uint256 listingId = entityTrading.listedTokenIds(TOKEN_ID);
    (
      address account,
      uint256 tokenId,
      uint256 price,
      bool isListed
    ) = entityTrading.listings(listingId);

    assertEq(account, address(0), 'Listing account should be zero address');
    assertEq(tokenId, 0, 'Listing token ID should be zero');
    assertEq(price, 0, 'Listing price should be zero');
    assertFalse(isListed, 'Listing should not be active');

    vm.stopPrank();
  }

  function test_nuked() public listNft {
    vm.deal(buyer, LISTING_PRICE);
    // vm.deal(address(entityTrading), LISTING_PRICE); // @audit - remove this line

    vm.startPrank(buyer);
    console.log('b4', address(entityTrading).balance);
    entityTrading.buyNFT{ value: LISTING_PRICE }(TOKEN_ID);
    console.log('after', address(entityTrading).balance);
    vm.stopPrank();

    uint256 acturalNukeFundBalance = address(nukeFund).balance;
    uint256 expectedNukeFundBalance = LISTING_PRICE / entityTrading.taxCut();

    assertEq(acturalNukeFundBalance, expectedNukeFundBalance);
  }

  modifier listNft() {
    nft.mintToken(owner);
    vm.startPrank(owner);
    nft.approve(address(entityTrading), TOKEN_ID);

    entityTrading.listNFTForSale(TOKEN_ID, LISTING_PRICE);

    uint256 listingId = entityTrading.listedTokenIds(TOKEN_ID);
    (
      address account,
      uint256 tokenId,
      uint256 price,
      bool isListed
    ) = entityTrading.listings(listingId);

    vm.stopPrank();

    assertEq(account, owner);
    assertEq(tokenId, TOKEN_ID);
    assertEq(price, LISTING_PRICE);
    assertTrue(isListed);
    _;
  }
}
