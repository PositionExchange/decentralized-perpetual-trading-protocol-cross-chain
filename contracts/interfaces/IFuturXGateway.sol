pragma solidity ^0.8.0;

interface IFuturXGateway {
    function executionFee() external returns (uint256);

    function maxGlobalShortSizes(address token) external view returns(uint256);

    function maxGlobalLongSizes(address token) external view returns(uint256);

    function getLatestIncreasePendingCollateral(
        address _account,
        address _indexToken,
        bool _isLong
    ) external view returns (address);
}
