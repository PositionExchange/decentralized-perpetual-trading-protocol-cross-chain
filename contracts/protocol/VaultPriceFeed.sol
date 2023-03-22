pragma solidity ^0.8.2;

import "../interfaces/IVaultPriceFeed.sol";

contract VaultPriceFeed is IVaultPriceFeed {
    function getPrice(
        address _token,
        bool _maximise
    ) external view override returns (uint256) {}
}
