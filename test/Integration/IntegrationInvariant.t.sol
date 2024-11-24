// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, StdInvariant, console2 } from 'forge-std/Test.sol';
import { IntegrationHandler } from './IntegrationHandler.t.sol';
import '../../contracts/EntityTrading/EntityTrading.sol';
import '../../contracts/test/TestERC721.sol';
import '../../contracts/NukeFund/NukeFund.sol';
import '../../contracts/TraitForgeNft/TraitForgeNft.sol';
import '../../contracts/DevFund/DevFund.sol';
import '../../contracts/Airdrop/Airdrop.sol';
import '../../contracts/EntityForging/EntityForging.sol';
import '../../contracts/EntityTrading/EntityTrading.sol';
import '../../contracts/EntropyGenerator/EntropyGenerator.sol';
import '../NukeFund/MerkleData.sol';

// import { ThePredicter } from '../../src/ThePredicter.sol';
// import { ScoreBoard } from '../../src/ScoreBoard.sol';

contract EntityTradingInvariant is StdInvariant, Test {
  IntegrationHandler handler;
  EntityTrading public entityTrading;
  // TestERC721 public nft;

  address public owner;
  address public buyer;

  NukeFund public nukeFund;
  TraitForgeNft public nft;
  DevFund public devFund;
  Airdrop public airdrop;
  EntityForging public entityForging;
  EntropyGenerator public entropyGenerator;

  // Merkle Tree
  MerkleData public merkleData;
  bytes32 public rootHash;
  address[] public whitelistAddresses;
  mapping(address => bytes32) public leafNodes;
  mapping(address => bytes32[]) public proofs;

  function setUp() public {
    owner = address(0x1);
    buyer = address(0x2);

    // Set Up Merkle Tree
    merkleData = new MerkleData();
    rootHash = merkleData.getRootHash();

    MerkleData.WhitelistEntry[] memory entries = merkleData
      .getWhitelistEntries();
    for (uint i = 0; i < entries.length; i++) {
      whitelistAddresses.push(entries[i].addr);
      leafNodes[entries[i].addr] = entries[i].leaf;
      proofs[entries[i].addr] = entries[i].proof;
    }
    //nukeFund = address(0x2);

    vm.startPrank(owner);
    // Set Up TraitForgeNft
    nft = new TraitForgeNft();

    // Set Up DevFund
    devFund = new DevFund();
    devFund.addDev(owner, 1);

    // Deploy and setup Airdrop
    airdrop = new Airdrop();
    nft.setAirdropContract(address(airdrop));
    airdrop.transferOwnership(address(nft));

    entityTrading = new EntityTrading(address(nft));
    entityTrading.setNukeFundAddress(payable(nukeFund));

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
    vm.roll(107);
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
    // bytes32[] memory proof = merkleData.getProofForAddress(owner);
    // vm.deal(owner, 1 ether);
    // nft.mintToken{ value: 1 ether }(proof);
    // Set minimumDaysHeld to 0 for testing purpose
    nukeFund.setMinimumDaysHeld(0);
    vm.stopPrank();

    handler = new IntegrationHandler(
      entityTrading,
      nft,
      owner,
      buyer,
      nukeFund,
      merkleData,
      entityForging,
      entropyGenerator
    );

    bytes4[] memory selectors = new bytes4[](6);
    // selectors[0] = handler.ListNFTForSale.selector;
    // selectors[1] = handler.buyNFT.selector;
    // selectors[2] = handler.cancelListing.selector;
    // selectors[3] = handler.nukeToken.selector;
    // selectors[0] = handler.enterGame.selector;
    selectors[0] = handler.ListNFTForForging.selector;
    selectors[1] = handler.mergeWithListedToken.selector;
    selectors[2] = handler.ListNFTForSale.selector;
    selectors[3] = handler.buyNFT.selector;
    selectors[4] = handler.cancelListing.selector;
    selectors[5] = handler.nukeToken.selector;

    targetSelector(
      FuzzSelector({ addr: address(handler), selectors: selectors })
    );
    targetContract(address(handler));
  }

  //https://claude.ai/chat/dd22bd9c-4237-48b3-beae-3baaa0afc55b
  function invariant_integration() public {
    // console2.log('Invariance check', handler.buyingCount());
    // console2.log('NFT Count', nft.totalSupply());

    // Trading Revenue
    uint256 totalSales = handler.buyingCount() * handler.LISTING_PRICE();
    uint256 tradingProceeds = totalSales / entityTrading.taxCut();
    uint256 devSharesFromTrading = tradingProceeds / nukeFund.taxCut();

    // Minting Revenue
    uint256 totalMinted = handler.totalMints();
    console2.log('totalMinted', totalMinted);
    uint256 totalMintingFunds = 0;
    uint256 startPrice = nft.startPrice();
    uint256 priceIncrement = nft.priceIncrement();

    for (uint256 i = 0; i < totalMinted; i++) {
      totalMintingFunds += startPrice + (priceIncrement * i);
    }

    // Total DevFund shares
    uint256 devSharesFromMinting = totalMintingFunds / nukeFund.taxCut();
    uint256 totalDevShares = devSharesFromTrading + devSharesFromMinting;
    console2.log('mergedCount', handler.mergedCount());
    console2.log('buyingCount', handler.buyingCount());
    console2.log('cancelListingCounts', handler.cancelListingCounts());

    // Nuking Revenue
    // - calculateNukeFactor

    console2.log('buyer nft balance', nft.balanceOf(buyer));

    // assertEq(
    //   0,
    //   address(entityTrading).balance,
    //   'entityTrading balance mismatch'
    // );

    // // @todo - check inverse is tru for balance of nukeFund contract
    // assertEq(
    //   totalDevShares,
    //   address(devFund).balance,
    //   'devFund balance mismatch'
    // );

    //console.log('claimAmount', handler.claimAmount());
    console2.log('buyer.balance', buyer.balance);
  }
}
