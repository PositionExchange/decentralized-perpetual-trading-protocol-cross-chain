pragma solidity ^0.8.0;

interface IFuturXGateway {
    function executionFee() external returns (uint256);

    function maxGlobalShortSizes(address token) external view returns (uint256);

    function maxGlobalLongSizes(address token) external view returns (uint256);

    function gatewayStorage() external view returns (address);

    function isPaused() external view returns (bool);

    function coreManagers(address token) external view returns (address);

    function pcsId() external view returns (uint256);

    function pscCrossChainGateway() external view returns (address);

    function futuresAdapter() external view returns (address);

    function positionKeepers(address caller) external view returns (bool);

    function indexTokens(address token) external view returns (address);

    function executeDecreasePosition(
        bytes32 _key,
        uint256 _amountOutAfterFeesUsd,
        uint256 _feeUsd,
        uint256 _entryPrice,
        uint256 _sizeDeltaToken,
        bool _isLong,
        bool _isExecutedFully
    ) external;
}
