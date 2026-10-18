# SQUEEK (SQK)

SQUEEK is an immutable ERC-20 token. Its constructor mints exactly **1,000,000,000 SQK** with **18 decimals** to the immediate deployer. All transfers deliver the requested amount.

| Deployment parameter | Value |
| --- | --- |
| Contract | `src/SqueekToken.sol:SqueekToken` |
| Solidity identifier | `SqueekToken` |
| Name / symbol | `SQUEEK` / `SQK` |
| Decimals | `18` |
| Total supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Deployment value | `0` ETH |
| Initial recipient | Constructor `msg.sender` |
| Intended launch chain | Ethereum, chain ID `1` |
| Compiler / EVM target | Solidity `0.8.26` / Cancun |
| Optimizer | Enabled, 200 runs |
| Bytecode metadata hash | `none` |

`INITIAL_SUPPLY` is the only token-specific public constant. Supply, name, symbol, and decimals have no setters. The deployed token has no owner, minter, pause, blacklist, seizure, burn, tax, upgrade, or initialization entry point. There are no application contracts or external services to configure.

## Build and test

Run from the repository root with Foundry and Solidity 0.8.26 installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x409afa54cf9bc567103ef74c91e913e6ca06e1f4541673c1541e128b2b062a74 forge test
forge fmt --check
```

OpenZeppelin Contracts v5.0.2 supplies the unchanged ERC-20 implementation. Forge Standard Library v1.9.7 supplies test utilities. All required source files and dependency licenses are vendored as ordinary files under `lib/`; builds and tests need no network after the compiler and Foundry are installed. [DEPENDENCIES.md](DEPENDENCIES.md) records source versions and archive checksums. FFI and filesystem cheatcode permissions are not enabled. Tests use local EVM state without RPCs, keys, environment reads, or environment writes.

The suite covers constructor minting and its event, metadata, CREATE2 factory ownership of the initial supply, full and zero transfers, self-transfers, contract recipients, approvals and revocations, finite and maximum allowances, delegated transfers, invalid recipients, insufficient funds or approvals, atomic failure, and absence of privileged entry points. It also checks runtime size and prohibited execution opcodes. Fuzz tests run 1,024 cases each. Two stateful invariants run 128 sequences of 64 calls each against an independent ledger, checking balances, supply, and allowances after successful and rejected operations.

The local distribution test checks exact 10% / 80% / 10% transfers, contributor transfers, and transfers to and from a pool custodian. It does not instantiate a Uniswap pool. The supplied protected launch tests require the network's factory, liquidity support contracts, launch manifest, and harness configuration; full pool seeding and swaps remain part of the network's independent verification.

## Deployment and operation

Deploy the creation bytecode for **SqueekToken**, without arguments or ETH. The constructor makes no external calls. Under the IdentityMD factory launch, the factory is `msg.sender` and receives every token; neither the caller of the factory nor the transaction origin receives tokens from the constructor. A direct deployment instead gives every token to the direct deployer. There is no separate recipient or owner parameter.

The network's deployment step is responsible for writing the launch manifest, deploying through the factory, distributing the supply, setting up liquidity, checking deployed bytecode and balances, and verifying the source on an explorer. No launch manifest is included here. Distribution percentages, pool fees, paired currency, and launch economics are handled by that step; the token does not allocate or reserve any portion of the supply itself. No transactions have been broadcast by this project.

### After launch

No administrative setup, owner-only setters, keepers, or ongoing token maintenance are required. Holders control their balances through `transfer` and authorize spenders through `approve`. The deployer has the same rights as every other holder after construction. The supply cannot be replenished or changed, and the contract cannot be upgraded or paused.

The implementation assumes ordinary ERC-20 behavior:

- `transfer`, `approve`, and `transferFrom` return `true` on success and revert with ERC-6093 custom errors on failure.
- Zero-value transfers between nonzero addresses are allowed and emit `Transfer`. Transfers to the zero address and approvals to the zero spender revert.
- `approve` replaces an existing allowance. When changing an allowance, holders should first revoke it with `approve(spender, 0)` and wait for confirmation before granting a new amount; pending spending can otherwise race a replacement. Prefer approving only the amount needed.
- Maximum `uint256` allowance is treated as unlimited and is not reduced by `transferFrom`. Other allowances decrease by the amount spent. `approve` emits `Approval`; this OpenZeppelin version does not emit a new `Approval` when `transferFrom` spends allowance. Integrations should read `allowance` for its current value.
- Transfers do not call recipient code. Holders must check destination addresses and contract support for recovering tokens. Tokens sent to this token contract, or another contract without a withdrawal path, cannot be recovered by an administrator. Plain ETH transfers revert, and there is no asset rescue mechanism.

## Review scope

The implementation was reviewed against the supplied security reference for supply scaling, access control, allowance authorization, failure rollback, and external-call exposure. It adds only a constructor mint to OpenZeppelin ERC-20. It uses no oracle, signatures, randomness, external callbacks, proxy, or linked library. Foundry build, unit tests, fuzz tests, stateful invariants, and formatting checks are the local validation; Slither and Mythril were not run. This validation is not an independent security audit. The network's separate adversarial review and launch integration checks remain release responsibilities.
