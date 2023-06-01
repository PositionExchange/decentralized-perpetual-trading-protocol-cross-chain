// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IFuturXGatewayStorage {
    struct IncreasePositionRequest {
        address account;
        address[] path;
        address indexToken;
        bool hasCollateralInETH;
        uint256 amountInToken;
        uint256 feeUsd;
        uint256 positionFeeUsd;
        uint256 voucherId;
    }

    struct DecreasePositionRequest {
        address account;
        address[] path;
        address indexToken;
        bool withdrawETH;
    }

    struct UpdateCollateralRequest {
        address account;
        address[] path;
        address indexToken;
        uint256 amountInToken;
        bool isLong;
        uint256 feeToken;
    }

    function storeIncreasePositionRequest(IncreasePositionRequest memory _request)
        external
        returns (uint256, bytes32);

    function getIncreasePositionRequest(bytes32 _key)
        external
        view
        returns (IncreasePositionRequest memory);

    function getDeleteIncreasePositionRequest(bytes32 _key)
        external
        returns (IncreasePositionRequest memory);

    function storeUpdateCollateralRequest(UpdateCollateralRequest memory _request)
        external
        returns (uint256, bytes32);

    function getDeleteUpdateCollateralRequest(bytes32 _key)
        external
        returns (UpdateCollateralRequest memory);
}
