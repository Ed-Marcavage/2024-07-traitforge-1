// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract MerkleData {
  struct WhitelistEntry {
    address addr;
    bytes32 leaf;
    bytes32[] proof;
  }

  bytes32 private constant ROOT_HASH =
    0xf95c14e6953c95195639e8266ab1a6850864d59a829da9f9b13602ee522f672b;

  function getRootHash() public pure returns (bytes32) {
    return ROOT_HASH;
  }

  function getWhitelistEntries() public pure returns (WhitelistEntry[] memory) {
    WhitelistEntry[] memory entries = new WhitelistEntry[](2);

    entries[0].addr = 0x0000000000000000000000000000000000000001;
    entries[0]
      .leaf = 0x1468288056310c82aa4c01a7e12a10f8111a0560e72b700555479031b86c357d;
    entries[0].proof = new bytes32[](1);
    entries[0].proof[
        0
      ] = 0xd52688a8f926c816ca1e079067caba944f158e764817b83fc43594370ca9cf62;

    entries[1].addr = 0x0000000000000000000000000000000000000002;
    entries[1]
      .leaf = 0xd52688a8f926c816ca1e079067caba944f158e764817b83fc43594370ca9cf62;
    entries[1].proof = new bytes32[](1);
    entries[1].proof[
        0
      ] = 0x1468288056310c82aa4c01a7e12a10f8111a0560e72b700555479031b86c357d;

    return entries;
  }

  function getProofForAddress(
    address addr
  ) public pure returns (bytes32[] memory) {
    WhitelistEntry[] memory entries = getWhitelistEntries();
    for (uint i = 0; i < entries.length; i++) {
      if (entries[i].addr == addr) {
        return entries[i].proof;
      }
    }
    revert('Address not found in whitelist');
  }
}
