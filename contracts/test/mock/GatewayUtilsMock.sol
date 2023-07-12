// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "../../interfaces/IGatewayUtils.sol";

contract GatewayUtilsMock is IGatewayUtils {
    function calculateMarginFees(
        address _trader,
        address[] memory _path,
        address _indexToken,
        bool _isLong,
        uint256 _amountInToken,
        uint256 _amountInUsd,
        uint256 _leverage,
        bool _isLimitOrder
    ) external view returns (uint256, uint256, uint256) {
        return (0, 0, 0);
    }

    function calculateDiscountValue(
        uint256 _voucherId,
        uint256 _amountInUsd
    ) external view returns (uint256) {
        return (0);
    }

    function getPositionFee(
        address _indexToken,
        uint256 _amountInUsd,
        uint256 _leverage,
        bool _isLimitOrder
    ) external view returns (uint256) {
        return (0);
    }

    function getSwapFee(
        address[] memory _path,
        uint256 _amountInToken
    ) external view returns (uint256) {
        return (0);
    }

    function validateIncreasePosition(
        address _account,
        uint256 _msgValue,
        address[] memory _path,
        address _indexToken,
        uint256 _amountInUsd,
        uint256 _sizeDeltaToken,
        uint256 _pip,
        uint16 _leverage,
        bool _isLong,
        uint256 _voucherId
    ) external returns (bool) {
        return true;
    }

    function validateDecreasePosition(
        address _account,
        uint256 _msgValue,
        address[] memory _path,
        address _indexToken,
        uint256 _sizeDeltaToken,
        bool _isLong
    ) external returns (bool) {
        return true;
    }

    function validateSize(
        address _indexToken,
        uint256 _sizeDelta,
        bool _isCloseOrder
    ) external view returns (bool) {
        return true;
    }

    function validateMaxGlobalSize(
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta
    ) external view returns (bool) {
        return true;
    }

    function validateUpdateCollateral(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) external view returns (bool) {
        return true;
    }

    function validateTokens(
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) external view returns (bool) {
        return true;
    }

    function validateTokenWithdrawal(
        address[] memory _path,
        uint256 _amountOutToken
    ) external view override returns (bool) {
        return true;
    }

    function validateUsdWithdrawal(
        address[] memory _path,
        uint256 _amountOutToken
    ) external view override returns (bool) {
        return true;
    }
}
