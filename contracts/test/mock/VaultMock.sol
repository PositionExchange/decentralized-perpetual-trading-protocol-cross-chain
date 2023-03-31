pragma solidity ^0.8.2;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract VaultMock {
    using SafeMath for uint256;

    uint256 public tokenPriceMock = 1000;
    uint256 public tokenDecimalsMock = 1;
    mapping(bytes32 => uint256) public positionEntryFundingRates;
    mapping(address => uint256) public cumulativeFundingRates;

    function usdToTokenMin(
        address,
        uint256 _usdAmount
    ) public view returns (uint256) {
        return _usdAmount.div(tokenPriceMock);
    }

    function tokenToUsdMin(
        address,
        uint256 _tokenAmount
    ) public view returns (uint256) {
        return _tokenAmount.mul(tokenPriceMock);
    }

    function getFundingFee(
        address _trader,
        address _collateralToken,
        address _indexToken,
        uint256 _amountInUsd,
        bool _isLong
    ) external returns (uint256) {
        return 0;
    }
}
