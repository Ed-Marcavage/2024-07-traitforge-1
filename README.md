# [[H-06] mintToken(), mintWithBudget(), and forge() in the TraitForgeNft contract will fail due to a wrong modifier used in EntropyGenerator.initializeAlphaIndices()](https://github.com/code-423n4/2024-07-traitforge-findings/issues/752)

## Lines of code

https://github.com/code-423n4/2024-07-traitforge/blob/main/contracts/TraitForgeNft/TraitForgeNft.sol#L22
https://github.com/code-423n4/2024-07-traitforge/blob/main/contracts/TraitForgeNft/TraitForgeNft.sol#L280-L282
https://github.com/code-423n4/2024-07-traitforge/blob/main/contracts/TraitForgeNft/TraitForgeNft.sol#L334
https://github.com/code-423n4/2024-07-traitforge/blob/main/contracts/TraitForgeNft/TraitForgeNft.sol#L353
https://github.com/code-423n4/2024-07-traitforge/blob/main/contracts/EntropyGenerator/EntropyGenerator.sol#L206


## Vulnerability details

## Impact
In `TraitForgeNft`, when the token per generation reaches`TraitForgeNft::maxTokensPerGen` the contract tries to reset `generationMintCounts[currentGeneration] = 0` in `TraitForgeNft::_incrementGeneration`. However, this call will always fail due to incorrect access controls on `EntropyGenerator::initializeAlphaIndices`. Effectively making the contract unusable for minting & forging, halting the game's progress. The following functions will be uncallable when the token per generation reaches`TraitForgeNft::maxTokensPerGen`:
- `TraitForgeNft::mintToken`
- `TraitForgeNft::mintWithBudget`
- `TraitForgeNft::forge`


## Proof of Concept

```
function testIncorrectAccessControls() public {
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
```

Logs:
```
 ├─ [20008] TraitForgeNft::mintToken{value: 1000000000000000000}([0xd52688a8f926c816ca1e079067caba944f158e764817b83fc43594370ca9cf62])
  │   ├─ [2665] EntropyGenerator::initializeAlphaIndices()
  │   │   └─ ← [Revert] revert: Ownable: caller is not the owner
  │   └─ ← [Revert] revert: Ownable: caller is not the owner
  └─ ← [Revert] revert: Ownable: caller is not the owner
```
## Tools Used
Unit Test

## Recommended Mitigation Steps
```diff
+ modifier onlyAllowedCallerOrOwner() {
+   require(
+     msg.sender == allowedCaller || msg.sender == owner(),
+     'Caller is not allowed'
+   );
+   _;
+ }

function initializeAlphaIndices()
  public
  whenNotPaused
-   onlyOwner
+   onlyAllowedCallerOrOwner
{
  uint256 hashValue = uint256(
    keccak256(abi.encodePacked(blockhash(block.number - 1), block.timestamp))
  );

  uint256 slotIndexSelection = (hashValue % 258) + 512;
  uint256 numberIndexSelection = hashValue % 13;

  slotIndexSelectionPoint = slotIndexSelection;
  numberIndexSelectionPoint = numberIndexSelection;
}
```


## Assessed type

Access Control
