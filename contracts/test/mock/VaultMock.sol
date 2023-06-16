pragma solidity ^0.8.2;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract VaultMock {
    using SafeMath for uint256;

    uint256 public tokenPriceMock = 1000;
    uint256 public tokenDecimalsMock = 1;
    mapping(address => uint256) public tokenConfigurations;
    mapping(address => uint256) public priceMock;

    function usdToTokenMin(
        address _token,
        uint256 _usdAmount
    ) public view returns (uint256) {
        uint256 decimals = tokenConfigurations[_token];
        uint256 price = priceMock[_token];

        return _usdAmount.mul(10 ** decimals).div(price);
    }

    function tokenToUsdMin(
        address,
        uint256 _tokenAmount
    ) public view returns (uint256) {
        return _tokenAmount.mul(tokenPriceMock);
    }

    function tokenToUsdMinWithAdjustment(
        address,
        uint256 _tokenAmount
    ) public view returns (uint256) {
        return _tokenAmount.mul(tokenPriceMock);
    }

    function getBorrowingFee(
        address _trader,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) external view returns (uint256) {
        return 0;
    }

    function setTokenConfigurations(address _token, uint256 _decimal) external {
        tokenConfigurations[_token] = _decimal;
    }

    function setPriceMock(address _token, uint256 _price) external {
        priceMock[_token] = _price;
    }
}
