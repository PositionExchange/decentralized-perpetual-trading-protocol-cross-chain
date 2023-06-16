// SPDX-License-Identifier: MIT
// mocking only

pragma solidity ^0.8.9;

import "../MintableBaseToken.sol";

contract POSI is MintableBaseToken {
    constructor() public MintableBaseToken("POSI", "POSI", 0) {}
}
