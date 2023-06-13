// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./IVault.sol";

interface IFuturXGatewayStorage {
    enum OpCode {
        IncreasePosition,
        DecreasePosition,
        UpdateCollateral
    }
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

    struct PendingCollateral {
        uint16 count;
        address collateral;
    }

    struct UpPendingCollateralParam {
        address account;
        address indexToken;
        address collateralToken;
        uint8 op;
    }

    function getRequestKey(address _account, uint256 _index, OpCode _op)
        external
        view
        returns (bytes32);

    function getTPSLRequestKey(
        address _account,
        address _indexToken,
        bool _isHigherPip
    ) external pure returns (bytes32);

    function getIncreasePositionRequest(bytes32 _key)
        external
        view
        returns (IncreasePositionRequest memory);

    function getDeleteIncreasePositionRequest(bytes32 _key)
        external
        returns (IncreasePositionRequest memory);

    function getUpdateOrDeleteIncreasePositionRequest(
        bytes32 _key,
        uint256 amountInToken,
        bool isExecutedFully,
        IVault vault,
        uint16 leverage
    )   external
        returns (IncreasePositionRequest memory);


    function getDecreasePositionRequest(bytes32 _key)
        external
        view
        returns (DecreasePositionRequest memory);

    function getDeleteDecreasePositionRequest(bytes32 _key)
        external
        returns (DecreasePositionRequest memory);

    function getDeleteUpdateCollateralRequest(bytes32 _key)
        external
        returns (UpdateCollateralRequest memory);

    function getPendingCollateral(address _account, address _indexToken)
        external
        returns (PendingCollateral memory);

    function storeIncreasePositionRequest(
        IncreasePositionRequest memory _request
    ) external returns (uint256, bytes32);

    function storeDecreasePositionRequest(
        DecreasePositionRequest memory _request
    ) external returns (uint256, bytes32);

    function storeUpdateCollateralRequest(
        UpdateCollateralRequest memory _request
    ) external returns (uint256, bytes32);

    function storeTpslRequest(
        address _account,
        address _indexToken,
        bool _isHigherPip,
        bytes32 _decreasePositionRequestKey
    ) external;

    function deleteDecreasePositionRequest(bytes32 _key) external;

    function deleteTpslRequest(
        address _account,
        address _indexToken,
        bool _isHigherPip
    ) external;

    function updatePendingCollateral(UpPendingCollateralParam memory param)
        external
        returns (bytes32);
}
