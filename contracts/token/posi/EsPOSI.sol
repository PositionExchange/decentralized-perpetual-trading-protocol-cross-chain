// SPDX-License-Identifier: MIT
// mocking only

pragma solidity ^0.8.2;

import "../MintableBaseToken.sol";

contract EsPOSI is MintableBaseToken {
    constructor() public MintableBaseToken("Escrowed POSI", "esPOSI", 0) {}
}
