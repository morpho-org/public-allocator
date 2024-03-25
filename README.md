# Public Allocator

## Overview

[MetaMorpho](https://github.com/morpho-org/metamorpho) is a protocol for funds allocations and risk management on top of [Morpho Blue](https://github.com/morpho-org/morpho-blue). The Public Allocator is a contract that MetaMorpho curators can enabled as [allocator](https://github.com/morpho-org/metamorpho?tab=readme-ov-file#allocator) to let anybody reallocate the vault's funds to fill their liquidity needs.

The Public Allocator's function `reallocateTo` reallocates some liquidity from multiple markets to one market. It takes as input `withdrawals`, a list of `(MarketParams, uint128)` pairs, which will be the markets and amounts that will be reallocated, and `supplyMarketParams`, a `MarketParams`, which is the market in which to supply the reallocated funds. Note that the markets in `withdrawals` must have their `id` sorted, and that `supplyMarketParams` cannot be a market of `withdrawals`.

The Public Allocator provides the possibility to the vault owner or a per vault settable admin to constrain the public reallocation:
- **Max flows**: Each market has a max inflow (`maxIn`) and max outflow (`maxOut`), that can be set by the vault owner or the admin. The markets from which funds are withdrawn through `reallocateTo` increase their `maxIn` and decrease their `maxOut`, and the market in which funds are deposited decrease their `maxOut` and increase their `maxIn`.
- **Fee**: If set, user must pay a fee in ETH to be able to call `reallocateTo`. The vault owner or admin can set this fee. The vault owner or admin can take the accumulated fees out of the Public Allocator by calling `transferFee`.

## Testing

To run tests: `forge test`. Note that running the tests this way will use this repository's compilation settings for dependencies (Morpho & MetaMorpho), potentially different from the settings used for deployment of those dependencies.

## Audits

All audits are stored in the [audits](./audits/)' folder.

## Licence

All files are licenced under `GPL-2.0-or-later`, see [`LICENCE`](./LICENCE).
