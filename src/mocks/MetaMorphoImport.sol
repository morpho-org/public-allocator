// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;
// Force foundry to compile MetaMorpho even though it's not imported by the public allocator or by the tests.
// MetaMorpho will be compiled with its own solidity version.
// The resulting bytecode is then loaded by the tests.

import "../../lib/metamorpho/src/MetaMorpho.sol";
