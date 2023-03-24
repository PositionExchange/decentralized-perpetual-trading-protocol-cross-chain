pragma solidity ^0.8.2;

import "./MintableBaseToken.sol";
contract PLP is MintableBaseToken {
    constructor() MintableBaseToken("DPTP LP", "PLP", 0) {
    }
}

