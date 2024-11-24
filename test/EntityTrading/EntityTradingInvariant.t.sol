// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, StdInvariant, console2 } from 'forge-std/Test.sol';
import { EntityTradingHandler } from './EntityTradingHandler.t.sol';
import '../../contracts/EntityTrading/EntityTrading.sol';
import '../../contracts/test/TestERC721.sol';

// import { ThePredicter } from '../../src/ThePredicter.sol';
// import { ScoreBoard } from '../../src/ScoreBoard.sol';

contract EntityTradingInvariant is StdInvariant, Test {
  EntityTradingHandler handler;
  EntityTrading public entityTrading;
  TestERC721 public nft;

  address public owner;
  address public buyer;
  address public nukeFund;

  function setUp() public {
    owner = address(0x3);
    buyer = address(0x1);
    nukeFund = address(0x2);

    vm.startPrank(owner);
    nft = new TestERC721();

    entityTrading = new EntityTrading(address(nft));
    entityTrading.setNukeFundAddress(payable(nukeFund));
    vm.stopPrank();

    handler = new EntityTradingHandler(
      entityTrading,
      nft,
      owner,
      buyer,
      nukeFund
    );

    bytes4[] memory selectors = new bytes4[](3);
    selectors[0] = handler.ListNFTForSale.selector;
    selectors[1] = handler.buyNFT.selector;
    selectors[2] = handler.cancelListing.selector;

    targetSelector(
      FuzzSelector({ addr: address(handler), selectors: selectors })
    );
    targetContract(address(handler));
  }

  function invariant_trading() public {
    console2.log('Invariance check', handler.buyingCount());
    uint256 actualNukeFundBalance = address(nukeFund).balance;
    if (handler.buyingCount() == 0) {
      return;
    }

    uint256 totalSales = handler.buyingCount() * handler.LISTING_PRICE();
    uint256 expectedNukeFundBalance = totalSales / entityTrading.taxCut();
    uint256 expectedTotalSellerProceeds = totalSales - expectedNukeFundBalance;

    assertEq(
      actualNukeFundBalance,
      expectedNukeFundBalance,
      'NukeFund balance mismatch'
    );
    assertEq(
      address(owner).balance,
      expectedTotalSellerProceeds,
      'Total seller proceeds mismatch'
    );
  }
}
