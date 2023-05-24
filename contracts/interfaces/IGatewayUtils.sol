pragma solidity ^0.8.2;

interface IGatewayUtils {
    function calculateMarginFees(
        address _trader,
        address[] memory _path,
        address _indexToken,
        bool _isLong,
        uint256 _amountInToken,
        uint256 _amountInUsd,
        uint256 _leverage,
        bool _isLimitOrder
    )
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        );

    function calculateDiscountValue(uint256 _voucherId, uint256 _amountInUsd)
        external
        view
        returns (uint256);

    function getPositionFee(
        address _indexToken,
        uint256 _amountInUsd,
        uint256 _leverage,
        bool _isLimitOrder
    ) external view returns (uint256);

    function getSwapFee(address[] memory _path, uint256 _amountInToken)
        external
        view
        returns (uint256);

    function validateIncreasePosition(
        address _account,
        uint256 _msgValue,
        address[] memory _path,
        address _indexToken,
        uint256 _sizeDeltaToken,
        uint16 _leverage,
        bool _isLong,
        uint256 _voucherId
    ) external returns (bool);

    function validateDecreasePosition(
        address _account,
        uint256 _msgValue,
        address[] memory _path,
        address _indexToken,
        uint256 _sizeDeltaToken,
        bool _isLong
    ) external returns (bool);

    function validateSize(
        address _indexToken,
        uint256 _sizeDelta,
        bool _isCloseOrder
    ) external view returns (bool);

    function validateMaxGlobalSize(
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta
    ) external view returns (bool);

    function validateUpdateCollateral(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) external view returns (bool);

    function validateTokens(
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) external view returns (bool);
}
