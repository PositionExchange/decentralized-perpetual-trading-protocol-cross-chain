pragma solidity ^0.8.9;

import "./MintableBaseToken.sol";

contract PLP is MintableBaseToken {
    constructor() MintableBaseToken("DPTP LP", "PLP", 0) {}
}
