# Notes

## Merkle distribution

- To distribute the tokens while they are locked, we need to approve some contract that has the ability to transfer tokens at all times. For this we can use Ownable and ensure that only the owner of the contracts can transfer the tokens but we also need to distribute some of the tokens through a Merkle distributor. This would introduce the requirement that multiple contracts need to be able to make transfers during the locked period. There are two possible solutions for this issue:
  - Simple Solution: Continue to use Ownable and approve the entire airdrop amount for the Merkle contract to transfer directly from the Owner of Ownable.
  - More complex: Instead of using Ownable, use AccessControl and allow multiple addresses to transfer tokens at any time.

> Note: We may need to do the same thing for vesting contracts as well.

