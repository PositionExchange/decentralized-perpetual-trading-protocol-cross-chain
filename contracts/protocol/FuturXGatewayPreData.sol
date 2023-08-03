/**
 * @author Musket
 */
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import "./common/CrosscallMethod.sol";
import "../interfaces/IGatewayUtils.sol";
import "./DptpFuturesGateway.sol";
import "../interfaces/IFullyDptpFuturesGateway.sol";

contract FuturXGatewayPreData is OwnableUpgradeable, CrosscallMethod {
    using SafeMathUpgradeable for uint256;
    using SafeCastUpgradeable for uint256;

    enum SetTPSLOption {
        BOTH,
        HIGHER,
        LOWER
    }

    uint256 constant PRICE_DECIMALS = 10 ** 12;

    IGatewayUtils public gatewayUtils;
    IVault public vault;
    IFuturXGatewayStorage public futurXGatewayStorage;
    IFullyDptpFuturesGateway public futurXGateway;

    struct CreateIncreasePositionPre {
        address positionManager;
        bool isLong;
        uint256 sizeDeltaToken;
        uint16 leverage;
        uint256 amountInUsd;
        uint256 pip;
        address user;
    }

    struct CreateDecreasePositionPre {
        address positionManager;
        uint256 sizeDeltaToken;
        uint256 pip;
        address user;
    }

    struct CreateCancelOrderPre {
        address positionManager;
        uint256 orderIdx;
        bool isReduce;
        address user;
    }

    struct CreateAddCollateralPre {
        address positionManager;
        uint256 amountInUsd;
        address user;
    }

    struct CreateRemoveCollateralPre {
        address positionManager;
        uint256 amountOutUsd;
        address user;
    }

    struct SetTPSLPre {
        address positionManager;
        address user;
        uint128 higherPip;
        uint128 lowerPip;
        SetTPSLOption option;
    }

    struct UnsetTPAndSLPre {
        address positionManager;
        address user;
    }

    struct UnsetTPOrSLPre {
        address positionManager;
        address user;
        bool isHigher;
    }

    function initialize(
        address _futurXGateway,
        address _vault,
        address _gatewayUtils,
        address _futurXGatewayStorage
    ) external initializer {
        __Ownable_init();
        futurXGateway = IFullyDptpFuturesGateway(_futurXGateway);
        vault = IVault(_vault);
        gatewayUtils = IGatewayUtils(_gatewayUtils);
        futurXGatewayStorage = IFuturXGatewayStorage(futurXGatewayStorage);
    }

    function createIncreasePositionRequest(
        address[] memory _path,
        address _indexToken,
        uint256 _amountInUsd,
        uint256 _sizeDeltaToken,
        uint16 _leverage,
        bool _isLong,
        uint256 _voucherId,
        address _user
    )
        public
        view
        returns (CreateIncreasePositionPre memory params, Method method)
    {
        params = CreateIncreasePositionPre({
            positionManager: _indexTokenToManager(_indexToken),
            isLong: _isLong,
            sizeDeltaToken: _sizeDeltaToken,
            leverage: _leverage,
            amountInUsd: _amountInUsd,
            pip: 0,
            user: _user
        });
        method = Method.OPEN_MARKET;
    }

    function createIncreaseOrderRequest(
        address[] memory _path,
        address _indexToken,
        uint256 _amountInUsd,
        uint256 _pip,
        uint256 _sizeDeltaToken,
        uint16 _leverage,
        bool _isLong,
        uint256 _voucherId,
        address _user
    )
        external
        view
        returns (CreateIncreasePositionPre memory params, Method method)
    {
        {
            address[] memory path = _path;
            params = CreateIncreasePositionPre({
                positionManager: _indexTokenToManager(_indexToken),
                isLong: _isLong,
                sizeDeltaToken: _sizeDeltaToken,
                leverage: _leverage,
                amountInUsd: _amountInUsd,
                pip: _pip,
                user: _user
            });
        }
        method = Method.OPEN_LIMIT;
    }

    function createDecreasePositionRequest(
        address _indexToken,
        uint256 _sizeDeltaToken,
        address _user
    )
        external
        view
        returns (CreateDecreasePositionPre memory params, Method method)
    {
        params = CreateDecreasePositionPre({
            positionManager: _indexTokenToManager(_indexToken),
            sizeDeltaToken: _sizeDeltaToken,
            pip: 0,
            user: _user
        });
        method = Method.CLOSE_POSITION;
    }

    function createDecreaseOrderRequest(
        address _indexToken,
        uint256 _pip,
        uint256 _sizeDeltaToken,
        address _user
    )
        external
        view
        returns (CreateDecreasePositionPre memory params, Method method)
    {
        params = CreateDecreasePositionPre({
            positionManager: _indexTokenToManager(_indexToken),
            sizeDeltaToken: _sizeDeltaToken,
            pip: _pip,
            user: _user
        });
        method = Method.CLOSE_LIMIT_POSITION;
    }

    function createCancelOrderRequest(
        bytes32 _key,
        uint256 _orderIdx,
        bool _isReduce
    ) public view returns (CreateCancelOrderPre memory param, Method method) {
        address user;
        address indexToken;

        if (_isReduce) {
            IFuturXGatewayStorage.DecreasePositionRequest
                memory request = _getDecreasePositionRequest(_key);
            user = request.account;
            indexToken = request.indexToken;
        } else {
            IFuturXGatewayStorage.IncreasePositionRequest
                memory request = _getIncreasePositionRequest(_key);
            user = request.account;
            indexToken = request.indexToken;
        }

        param = CreateCancelOrderPre({
            positionManager: _indexTokenToManager(indexToken),
            orderIdx: _orderIdx,
            isReduce: _isReduce,
            user: user
        });
        method = Method.CANCEL_LIMIT;
    }

    function createAddCollateralRequest(
        address[] memory _path,
        address _indexToken,
        uint256 _amountInToken,
        address _user
    )
        external
        view
        returns (CreateAddCollateralPre memory params, Method method)
    {
        address paidToken = _path[0];
        address collateralToken = _path[_path.length - 1];

        _amountInToken = _adjustDecimalToToken(paidToken, _amountInToken);

        uint256 swapFeeToken = paidToken == collateralToken
            ? 0
            : gatewayUtils.getSwapFee(_path, _amountInToken);

        uint256 swapFeeUsd = _tokenToUsdMin(collateralToken, swapFeeToken);
        uint256 amountInUsd = _tokenToUsdMin(paidToken, _amountInToken).sub(
            swapFeeUsd
        );

        params = CreateAddCollateralPre({
            positionManager: _indexTokenToManager(_indexToken),
            amountInUsd: amountInUsd.div(PRICE_DECIMALS),
            user: _user
        });
        method = Method.ADD_MARGIN;
    }

    function createRemoveCollateralRequest(
        address[] memory _path,
        address _indexToken,
        uint256 _amountOutUsd,
        address _user
    )
        external
        view
        returns (CreateRemoveCollateralPre memory params, Method method)
    {
        address collateralToken = _path[0];

        uint256 amountOutUsdFormatted = _amountOutUsd.mul(PRICE_DECIMALS);

        params = CreateRemoveCollateralPre({
            positionManager: _indexTokenToManager(_indexToken),
            amountOutUsd: _amountOutUsd,
            user: _user
        });
        method = Method.REMOVE_MARGIN;
    }

    function setTPSL(
        address _indexToken,
        uint128 _higherPip,
        uint128 _lowerPip,
        SetTPSLOption _option,
        address _user
    ) external view returns (SetTPSLPre memory params, Method method) {
        params = SetTPSLPre({
            positionManager: _indexTokenToManager(_indexToken),
            user: _user,
            higherPip: _higherPip,
            lowerPip: _lowerPip,
            option: _option
        });
        method = Method.SET_TPSL;
    }

    function unsetTPAndSL(
        address _indexToken,
        address _user
    ) external view returns (UnsetTPAndSLPre memory params, Method method) {
        params = UnsetTPAndSLPre(_indexTokenToManager(_indexToken), _user);
        method = Method.UNSET_TP_AND_SL;
    }

    function unsetTPOrSL(
        address _indexToken,
        bool _isHigherPrice,
        address _user
    ) external view returns (UnsetTPOrSLPre memory params, Method method) {
        params = UnsetTPOrSLPre({
            positionManager: _indexTokenToManager(_indexToken),
            user: _user,
            isHigher: _isHigherPrice
        });

        method = Method.UNSET_TP_OR_SL;
    }

    function _indexTokenToManager(
        address _indexToken
    ) internal view returns (address) {
        return futurXGateway.coreManagers(_indexToken);
    }

    function _collectFees(
        address _user,
        address[] memory _path,
        address _indexToken,
        uint256 _amountInToken,
        uint256 _amountInUsd,
        uint16 _leverage,
        bool _isLong,
        bool _isLimitOrder
    ) internal view returns (uint256 positionFeeUsd, uint256 totalFeeUsd) {
        {
            uint256 swapFeeUsd;
            (positionFeeUsd, swapFeeUsd, totalFeeUsd) = gatewayUtils
                .calculateMarginFees(
                    _user,
                    _path,
                    _indexToken,
                    _isLong,
                    _amountInToken,
                    _amountInUsd,
                    _leverage,
                    _isLimitOrder
                );
        }
        return (positionFeeUsd, totalFeeUsd);
    }

    function _usdToTokenMin(
        address _token,
        uint256 _usdAmount
    ) private view returns (uint256) {
        return vault.usdToTokenMin(_token, _usdAmount);
    }

    function _tokenToUsdMin(
        address _token,
        uint256 _tokenAmount
    ) private view returns (uint256) {
        return vault.tokenToUsdMin(_token, _tokenAmount);
    }

    function _adjustDecimalToToken(
        address _token,
        uint256 _tokenAmount
    ) internal view returns (uint256) {
        return vault.adjustDecimalToToken(_token, _tokenAmount);
    }

    function _getIncreasePositionRequest(
        bytes32 _key
    )
        internal
        view
        returns (IFuturXGatewayStorage.IncreasePositionRequest memory)
    {
        return futurXGatewayStorage.getIncreasePositionRequest(_key);
    }

    function _getDecreasePositionRequest(
        bytes32 _key
    )
        internal
        view
        returns (IFuturXGatewayStorage.DecreasePositionRequest memory)
    {
        return futurXGatewayStorage.getDecreasePositionRequest(_key);
    }

    function setFuturXGatewayStorage(
        IFuturXGatewayStorage _futurXGatewayStorage
    ) external onlyOwner {
        futurXGatewayStorage = _futurXGatewayStorage;
    }

    function setVault(IVault _vault) external onlyOwner {
        vault = _vault;
    }

    function setGatewayUtils(IGatewayUtils _gatewayUtils) external onlyOwner {
        gatewayUtils = _gatewayUtils;
    }

    function setFuturXGateway(
        IFullyDptpFuturesGateway _futurXGateway
    ) external onlyOwner {
        futurXGateway = _futurXGateway;
    }
}
