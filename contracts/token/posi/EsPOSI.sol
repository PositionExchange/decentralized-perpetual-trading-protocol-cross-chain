// SPDX-License-Identifier: MIT
// mocking only

pragma solidity ^0.8.9;

import "../MintableBaseToken.sol";

contract EsPOSI is MintableBaseToken {
    constructor() public MintableBaseToken("Escrowed POSI", "esPOSI", 0) {}
}
