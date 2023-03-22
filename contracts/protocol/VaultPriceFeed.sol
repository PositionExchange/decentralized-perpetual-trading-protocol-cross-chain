pragma solidity ^0.8.2;

import "../interfaces/IVaultPriceFeed.sol";
import "../oracle/interfaces/IPriceFeed.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract VaultPriceFeed is IVaultPriceFeed, Ownable {
    using SafeMath for uint256;
    uint256 public constant PRICE_PRECISION = 10 ** 30;

    mapping (address=>address) public priceFeeds;
    mapping (address => uint256) public priceDecimals;
    mapping (address => uint256) public spreadBasisPoints;

    function setPriceFeedConfig(address _token, address _priceFeed, uint256 _priceDecimals, uint256 _spreadBasisPoints) external onlyOwner {
      priceFeeds[_token] = _priceFeed;
      priceDecimals[_token] = _priceDecimals;
      spreadBasisPoints[_token] = _spreadBasisPoints;
    }

    function getPrice(
        address _token,
        bool _maximise
    ) external view override returns (uint256) {
      // mocking only
      // TODO get price more accurately
      uint256 price = getLatestChainlinkPrice(_token);
      uint256 _priceDecimals = priceDecimals[_token];
      return price.mul(PRICE_PRECISION).div(10 ** _priceDecimals);
    }

    function getLatestChainlinkPrice(address _token) public view returns(uint256) {
      address priceFeedAddress = priceFeeds[_token];
      require(priceFeedAddress != address(0), "VaultPriceFeed: invalid price feed");

      IPriceFeed priceFeed = IPriceFeed(priceFeedAddress);

      int256 price = priceFeed.latestAnswer();
      require(price > 0, "VaultPriceFeed: invalid price");

      return uint256(price);
    } 

    

}
