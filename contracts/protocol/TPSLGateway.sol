pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../interfaces/IFuturXGateway.sol";
import "../interfaces/IFuturXGatewayStorage.sol";
import "../interfaces/CrosschainFunctionCallInterface.sol";
import {Errors} from "./libraries/helpers/Errors.sol";
import "./common/CrosscallMethod.sol";

contract TPSLGateway is ReentrancyGuardUpgradeable, CrosscallMethod {
    IFuturXGateway public futurXGateway;

    enum SetTPSLOption {
        BOTH,
        HIGHER,
        LOWER
    }

    modifier whenNotPaused() {
        require(!futurXGateway.isPaused(), "Gateway is paused");
        _;
    }

    function initialize(address _futurXGateway) external initializer {
        __ReentrancyGuard_init();
        futurXGateway = IFuturXGateway(_futurXGateway);
    }

    function setTPSL(
        address[] memory _path,
        address _indexToken,
        bool _withdrawETH,
        uint128 _higherPip,
        uint128 _lowerPip,
        SetTPSLOption _option
    ) external nonReentrant whenNotPaused {
        (, bytes32 requestKey) = _storeDecreasePositionRequest(
            msg.sender,
            _path,
            _indexToken,
            _withdrawETH
        );

        if (_option == SetTPSLOption.HIGHER || _option == SetTPSLOption.BOTH) {
            _storeTpslRequest(msg.sender, _indexToken, true, requestKey);
        }

        if (_option == SetTPSLOption.LOWER || _option == SetTPSLOption.BOTH) {
            _storeTpslRequest(msg.sender, _indexToken, false, requestKey);
        }

        _crossBlockchainCall(
            uint8(Method.SET_TPSL),
            abi.encode(
                _indexTokenToManager(_indexToken),
                msg.sender,
                _higherPip,
                _lowerPip,
                uint8(_option)
            )
        );
    }

    function unsetTPAndSL(
        address _indexToken
    ) external nonReentrant whenNotPaused {
        _deleteTPSLRequestMap(msg.sender, _indexToken, true);
        _deleteTPSLRequestMap(msg.sender, _indexToken, false);

        _crossBlockchainCall(
            uint8(Method.UNSET_TP_AND_SL),
            abi.encode(_indexTokenToManager(_indexToken), msg.sender)
        );
    }

    function unsetTPOrSL(
        address _indexToken,
        bool _isHigherPrice
    ) external nonReentrant whenNotPaused {
        if (_isHigherPrice) {
            _deleteTPSLRequestMap(msg.sender, _indexToken, true);
        } else {
            _deleteTPSLRequestMap(msg.sender, _indexToken, false);
        }
        _crossBlockchainCall(
            uint8(Method.UNSET_TP_OR_SL),
            abi.encode(
                _indexTokenToManager(_indexToken),
                msg.sender,
                _isHigherPrice
            )
        );
    }

    function triggerTPSL(
        address _account,
        address _positionManager,
        uint256 _amountOutUsdAfterFees,
        uint256 _feeUsd,
        uint256 _sizeDeltaInToken,
        bool _isHigherPrice,
        bool _isLong
    ) external whenNotPaused {
        _validateCaller(msg.sender);

        address indexToken = futurXGateway.indexTokens(_positionManager);
        bytes32 key = gatewayStorage().getTPSLRequest(
            _account,
            indexToken,
            _isHigherPrice
        );
        futurXGateway.executeDecreasePosition(
            key,
            _amountOutUsdAfterFees,
            _feeUsd,
            0, // TODO: Add _entryPip
            _sizeDeltaInToken,
            _isLong,
            true
        );
        _deleteTPSLRequestMap(_account, indexToken, !_isHigherPrice);
        _deleteTPSLRequestMap(_account, indexToken, _isHigherPrice);
    }

    function _deleteTPSLRequestMap(
        address _account,
        address _indexToken,
        bool _isHigherPip
    ) private {
        gatewayStorage().deleteTpslRequest(_account, _indexToken, _isHigherPip);
    }

    function _storeTpslRequest(
        address _account,
        address _indexToken,
        bool _isHigherPip,
        bytes32 _decreasePositionRequestKey
    ) private {
        gatewayStorage().storeTpslRequest(
            _account,
            _indexToken,
            _isHigherPip,
            _decreasePositionRequestKey
        );
    }

    function _crossBlockchainCall(
        uint8 _destMethodID,
        bytes memory _functionCallData
    ) internal {
        CrosschainFunctionCallInterface(futurXGateway.futuresAdapter())
            .crossBlockchainCall(
                pscId(),
                pscCrossChainGateway(),
                _destMethodID,
                _functionCallData
            );
    }

    // get gateway storage return IFuturXGatewayStorage
    function gatewayStorage() private view returns (IFuturXGatewayStorage) {
        return IFuturXGatewayStorage(futurXGateway.gatewayStorage());
    }

    function _storeDecreasePositionRequest(
        address _account,
        address[] memory _path,
        address _indexToken,
        bool _withdrawETH
    ) internal returns (uint256, bytes32) {
        return
            gatewayStorage().storeDecreasePositionRequest(
                IFuturXGatewayStorage.DecreasePositionRequest(
                    _account,
                    _path,
                    _indexToken,
                    _withdrawETH,
                    0
                )
            );
    }

    function pscId() public view returns (uint256) {
        return futurXGateway.pcsId();
    }

    function pscCrossChainGateway() public view returns (address) {
        return futurXGateway.pscCrossChainGateway();
    }

    function _indexTokenToManager(
        address _indexToken
    ) internal view returns (address) {
        return futurXGateway.coreManagers(_indexToken);
    }

    function _validateCaller(address _account) private {
        require(
            futurXGateway.positionKeepers(_account),
            Errors.TPSL_CALLER_NOT_WHITELISTED
        );
    }
}
