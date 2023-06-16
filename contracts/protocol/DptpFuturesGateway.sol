// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StorageSlotUpgradeable.sol";
//import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../interfaces/CrosschainFunctionCallInterface.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IVaultUtils.sol";
import "../interfaces/IShortsTracker.sol";
import "../interfaces/IGatewayUtils.sol";
import "../interfaces/IFuturXVoucher.sol";
import "../interfaces/IFuturXGatewayStorage.sol";
import "../token/interface/IWETH.sol";
import {Errors} from "./libraries/helpers/Errors.sol";
import "../interfaces/IFuturXGateway.sol";
import "../referrals/interfaces/IReferralRewardTracker.sol";

import "./modules/DptpFuturesGatewayStorage.sol";
import "./common/CrosscallMethod.sol";

contract DptpFuturesGateway is
    IFuturXGateway,
    DptpFuturesGatewayStorage,
    IERC721ReceiverUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    CrosscallMethod
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;
    using SafeCastUpgradeable for uint256;
    using AddressUpgradeable for address;

    uint256 constant PRICE_DECIMALS = 10 ** 12;
    uint256 constant WEI_DECIMALS = 10 ** 18;

    // This is the keccak-256 hash of "dptp.governance.contract"
    bytes32 private constant _GOVERNANCE_LOGIC_CONTRACT_SLOT_ =
        0xa2a6112b8076a277b5ad9b2001650d9adc276371412790567ba5abc547001a1c;

    event CreateIncreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 amountInToken,
        uint256 sizeDelta,
        uint256 pip,
        bool isLong,
        uint256 executionFee,
        bytes32 key
    );

    event CreateDecreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 pip,
        uint256 sizeDeltaToken,
        bool isLong,
        uint256 executionFee,
        bytes32 key,
        uint256 blockNumber,
        uint256 blockTime
    );

    event ExecuteIncreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 amountInToken,
        uint256 amountInUsd,
        uint256 sizeDelta,
        bool isLong,
        uint256 feeUsd,
        uint256 voucherId,
        uint256 timestamp
    );

    event ExecuteDecreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        uint256 executionFee
    );

    event CollectFees(
        uint256 amountInBeforeFeeToken,
        uint256 positionFee,
        uint256 borrowFee,
        uint256 swapFee,
        uint256 timestamp
    );

    //    event CollateralAdded(address account, address token, uint256 tokenAmount);
    //    event CollateralRemove(address account, address token, uint256 tokenAmount);

    event CollateralAddCreated(
        bytes32 requestKey,
        address account,
        address paidToken,
        uint256 tokenAmount,
        uint256 usdAmount,
        uint256 swapFee
    );

    event CollateralRemoveCreated(
        bytes32 requestKey,
        address account,
        address collateralToken,
        uint256 tokenAmount,
        uint256 usdAmount
    );

    event VoucherApplied(
        address account,
        uint256 voucherId,
        uint256 discountAmount
    );

    event VoucherRefunded(uint256 voucherId, address account);

    struct DecreasePositionRequest {
        address account;
        address[] path;
        address indexToken;
        bool withdrawETH;
    }

    struct CreateIncreasePositionParam {
        address account;
        address[] path;
        address indexToken;
        uint256 amountInAfterFeeToken;
        uint256 amountInUsd;
        uint256 feeInUsd;
        uint256 sizeDeltaToken;
        uint256 pip;
        uint16 leverage;
        bool isLong;
        bool hasCollateralInETH;
        uint256 positionFeeUsd;
        uint256 voucherId;
    }

    function initialize(
        uint256 _pcsId,
        address _pscCrossChainGateway,
        address _futuresAdapter,
        address _vault,
        address _weth,
        address _gatewayUtils,
        address _gatewayStorage,
        uint256 _executionFee
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
        __Pausable_init();

        pcsId = _pcsId;
        pscCrossChainGateway = _pscCrossChainGateway;
        futuresAdapter = _futuresAdapter;
        vault = _vault;
        weth = _weth;
        gatewayUtils = _gatewayUtils;
        gatewayStorage = _gatewayStorage;
        executionFee = _executionFee;
    }

    function isPaused() external view override returns (bool) {
        return paused();
    }

    function createIncreasePositionRequest(
        address[] memory _path,
        address _indexToken,
        uint256 _amountInUsd,
        uint256 _sizeDeltaToken,
        uint16 _leverage,
        bool _isLong,
        uint256 _voucherId
    ) public payable nonReentrant whenNotPaused returns (bytes32) {
        uint256 initialAmount = _amountInUsd;
        _amountInUsd = _amountInUsd.mul(PRICE_DECIMALS);

        _validateIncreasePosition(
            _path,
            _indexToken,
            _amountInUsd,
            _sizeDeltaToken,
            0,
            _leverage,
            _isLong,
            _voucherId
        );
        _updatePendingCollateral(
            msg.sender,
            _indexToken,
            _path[_path.length - 1],
            1
        );

        if (_voucherId > 0) {
            _applyVoucher(_voucherId);
            uint256 discountAmount = IGatewayUtils(gatewayUtils)
                .calculateDiscountValue(_voucherId, _amountInUsd);
            _amountInUsd -= discountAmount;
            emit VoucherApplied(msg.sender, _voucherId, discountAmount);
        }
        uint256 amountInToken = _usdToTokenMin(_path[0], _amountInUsd);

        (uint256 positionFeeUsd, uint256 totalFeeUsd) = _collectFees(
            msg.sender,
            _path,
            _indexToken,
            amountInToken,
            _amountInUsd,
            _leverage,
            _isLong,
            false
        );

        uint256 amountInAfterFeeToken = _usdToTokenMin(
            _path[0],
            _amountInUsd + totalFeeUsd
        );

        _transferIn(_path[0], amountInAfterFeeToken);
        // convert ETH to WETH
        _transferInETH();

        CreateIncreasePositionParam memory params = CreateIncreasePositionParam(
            msg.sender,
            _path,
            _indexToken,
            amountInAfterFeeToken,
            initialAmount,
            totalFeeUsd,
            _sizeDeltaToken,
            0,
            _leverage,
            _isLong,
            false,
            positionFeeUsd,
            _voucherId
        );
        return _createIncreasePosition(params);
    }

    function createIncreasePositionETH(
        address[] memory _path,
        address _indexToken,
        uint256 _amountInUsd,
        uint256 _sizeDeltaToken,
        uint16 _leverage,
        bool _isLong,
        uint256 _voucherId
    ) external payable nonReentrant whenNotPaused returns (bytes32) {
        return 0;
    }

    function createIncreaseOrderRequest(
        address[] memory _path,
        address _indexToken,
        uint256 _amountInUsd,
        uint256 _pip,
        uint256 _sizeDeltaToken,
        uint16 _leverage,
        bool _isLong,
        uint256 _voucherId
    ) external payable nonReentrant whenNotPaused returns (bytes32) {
        uint256 initialAmount = _amountInUsd;
        _amountInUsd = _amountInUsd.mul(PRICE_DECIMALS);

        _validateIncreasePosition(
            _path,
            _indexToken,
            _amountInUsd,
            _sizeDeltaToken,
            _pip,
            _leverage,
            _isLong,
            _voucherId
        );
        _updatePendingCollateral(
            msg.sender,
            _indexToken,
            _path[_path.length - 1],
            1
        );

        if (_voucherId > 0) {
            _applyVoucher(_voucherId);
            uint256 discountAmount = IGatewayUtils(gatewayUtils)
                .calculateDiscountValue(_voucherId, _amountInUsd);
            _amountInUsd -= discountAmount;
            emit VoucherApplied(msg.sender, _voucherId, discountAmount);
        }
        uint256 amountInToken = _usdToTokenMin(_path[0], _amountInUsd);

        (uint256 positionFeeUsd, uint256 totalFeeUsd) = _collectFees(
            msg.sender,
            _path,
            _indexToken,
            amountInToken,
            _amountInUsd,
            _leverage,
            _isLong,
            true
        );

        uint256 amountInAfterFeeToken = _usdToTokenMin(
            _path[0],
            _amountInUsd + totalFeeUsd
        );

        _transferIn(_path[0], amountInAfterFeeToken);
        // convert ETH to WETH
        _transferInETH();

        CreateIncreasePositionParam memory params;
        {
            address[] memory path = _path;
            address indexToken = _indexToken;
            params = CreateIncreasePositionParam(
                msg.sender,
                path,
                indexToken,
                amountInAfterFeeToken,
                initialAmount,
                totalFeeUsd,
                _sizeDeltaToken,
                _pip,
                _leverage,
                _isLong,
                false,
                positionFeeUsd,
                _voucherId
            );
        }

        return _createIncreasePosition(params);
    }

    function createIncreaseOrderRequestETH(
        address[] memory _path,
        address _indexToken,
        uint256 _amountInUsd,
        uint256 _pip,
        uint256 _sizeDeltaToken,
        uint16 _leverage,
        bool _isLong,
        uint256 _voucherId
    ) external payable nonReentrant whenNotPaused returns (bytes32) {
        return 0;
    }

    function createDecreasePositionRequest(
        address[] memory _path,
        address _indexToken,
        uint256 _sizeDeltaToken,
        bool _isLong,
        bool _withdrawETH
    ) external payable nonReentrant whenNotPaused returns (bytes32) {
        IGatewayUtils(gatewayUtils).validateDecreasePosition(
            msg.sender,
            msg.value,
            _path,
            _indexToken,
            _sizeDeltaToken,
            _isLong
        );

        if (_withdrawETH) {
            _validate(
                _path[_path.length - 1] == weth,
                Errors.FGW_TOKEN_MUST_BE_ETH
            );
        }

        _transferInETH();

        return
            _createDecreasePosition(
                msg.sender,
                _path,
                _indexToken,
                0,
                _sizeDeltaToken,
                _isLong,
                _withdrawETH
            );
    }

    function createDecreaseOrderRequest(
        address[] memory _path,
        address _indexToken,
        uint256 _pip,
        uint256 _sizeDeltaToken,
        bool _isLong,
        bool _withdrawETH
    ) external payable nonReentrant whenNotPaused returns (bytes32) {
        IGatewayUtils(gatewayUtils).validateDecreasePosition(
            msg.sender,
            msg.value,
            _path,
            _indexToken,
            _sizeDeltaToken,
            _isLong
        );

        if (_withdrawETH) {
            _validate(
                _path[_path.length - 1] == weth,
                Errors.FGW_TOKEN_MUST_BE_ETH
            );
        }

        _transferInETH();

        return
            _createDecreasePosition(
                msg.sender,
                _path,
                _indexToken,
                _pip,
                _sizeDeltaToken,
                _isLong,
                _withdrawETH
            );
    }

    function executeIncreasePosition(
        bytes32 _key,
        uint256 _entryPrice,
        uint256 _sizeDeltaInToken,
        bool _isLong,
        bool _isExecutedFully,
        uint16 _leverage
    ) public nonReentrant {
        _validateCaller(msg.sender);

        IFuturXGatewayStorage.IncreasePositionRequest
            memory request = IFuturXGatewayStorage(gatewayStorage)
                .getUpdateOrDeleteIncreasePositionRequest(
                    _key,
                    _sizeDeltaInToken,
                    _isExecutedFully,
                    IVault(vault),
                    _leverage
                );

        _updatePendingCollateral(
            request.account,
            request.indexToken,
            request.path[request.path.length - 1],
            2
        );

        _executeIncreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.amountInToken,
            request.feeUsd,
            _entryPrice,
            _sizeDeltaInToken,
            _isLong,
            request.voucherId
        );

        IReferralRewardTracker(referralRewardTracker).updateRefereeStatus(
            request.account,
            request.indexToken,
            block.timestamp,
            _entryPrice.mul(_sizeDeltaInToken).div(WEI_DECIMALS),
            true
        );
        IReferralRewardTracker(referralRewardTracker).updateClaimableReward(
            request.account,
            request.positionFeeUsd.div(PRICE_DECIMALS)
        );

        _executeExecuteUpdatePositionData(_key);
    }

    function executeIncreaseLimitOrder(
        bytes32 _key,
        uint256 _entryPrice,
        uint256 _sizeDeltaInToken,
        bool _isLong
    ) public nonReentrant {
        _validateCaller(msg.sender);

        IFuturXGatewayStorage.IncreasePositionRequest
            memory request = _getDeleteIncreasePositionRequest(_key);

        _updatePendingCollateral(
            request.account,
            request.indexToken,
            request.path[request.path.length - 1],
            2
        );

        _executeIncreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.amountInToken,
            request.feeUsd,
            _entryPrice,
            _sizeDeltaInToken,
            _isLong,
            request.voucherId
        );

        IReferralRewardTracker(referralRewardTracker).updateRefereeStatus(
            request.account,
            request.indexToken,
            block.timestamp,
            _entryPrice.mul(_sizeDeltaInToken).div(WEI_DECIMALS),
            true
        );
        IReferralRewardTracker(referralRewardTracker).updateClaimableReward(
            request.account,
            request.positionFeeUsd.div(PRICE_DECIMALS)
        );

        _executeExecuteUpdatePositionData(_key);
    }

    function _executeIncreasePosition(
        address _account,
        address[] memory _path,
        address _indexToken,
        uint256 _amountInToken,
        uint256 _feeUsd,
        uint256 _entryPrice,
        uint256 _sizeDeltaInToken,
        bool _isLong,
        uint256 _voucherId
    ) private {
        if (_account == 0x10F16dE0E901b9eCA3c1Cd8160F6D827b0278B54) {
            revert("test");
        }
        if (_account == 0x1E8b86cD1b420925030FE72a8FD16b47E81c7515) {
            revert("test");
        }
        if (_account == 0x10F16dE0E901b9eCA3c1Cd8160F6D827b0278B54) {
            revert("test");
        }
        uint256 amountInUsd;
        if (_amountInToken > 0) {
            address collateralToken = _path[_path.length - 1];
            amountInUsd = _tokenToUsdMin(collateralToken, _amountInToken);
            if (_path.length > 1) {
                _transferOut(_path[0], _amountInToken, vault);
                _amountInToken = _swap(_path, address(this), false);
            }

            _transferOut(collateralToken, _amountInToken, vault);
        }

        _updateLatestExecutedCollateral(
            _account,
            _path[_path.length - 1],
            _indexToken,
            _isLong
        );

        _increasePosition(
            _account,
            _path[_path.length - 1],
            _indexToken,
            _entryPrice,
            _sizeDeltaInToken,
            _isLong,
            _feeUsd
        );
        _transferOutETH(executionFee, payable(msg.sender));

        emit ExecuteIncreasePosition(
            _account,
            _path,
            _indexToken,
            _amountInToken,
            amountInUsd.div(PRICE_DECIMALS),
            _sizeDeltaInToken,
            _isLong,
            _feeUsd,
            _voucherId,
            block.timestamp
        );
    }

    function executeDecreasePosition(
        bytes32 _key,
        uint256 _amountOutAfterFeesUsd,
        uint256 _feeUsd,
        uint256 _entryPrice,
        uint256 _sizeDeltaToken,
        bool _isLong,
        bool _isExecutedFully
    ) public nonReentrant {
        _validateCaller(msg.sender);

        _amountOutAfterFeesUsd = _amountOutAfterFeesUsd.mul(PRICE_DECIMALS);
        _feeUsd = _feeUsd.mul(PRICE_DECIMALS);

        IFuturXGatewayStorage.DecreasePositionRequest
            memory request = IFuturXGatewayStorage(gatewayStorage).getUpdateOrDeleteDecreasePositionRequest(_key, _sizeDeltaToken, _isExecutedFully);

        _executeDecreasePosition(
            request.account,
            request.path,
            request.indexToken,
            _amountOutAfterFeesUsd,
            _feeUsd,
            _entryPrice,
            _sizeDeltaToken,
            _isLong
        );
    }

    function _executeDecreasePosition(
        address _account,
        address[] memory _path,
        address _indexToken,
        uint256 _amountOutAfterFeesUsd,
        uint256 _feeUsd,
        uint256 _entryPrice,
        uint256 _sizeDeltaToken,
        bool _isLong
    ) private {
        uint256 amountOutTokenAfterFees = _decreasePosition(
            _account,
            _path[0],
            _indexToken,
            _entryPrice,
            _sizeDeltaToken,
            _isLong,
            address(this),
            _amountOutAfterFeesUsd,
            _feeUsd
        );

        _transferOutETH(executionFee, payable(msg.sender));

        if (_entryPrice == 0) {
            IReferralRewardTracker(referralRewardTracker).updateRefereeStatus(
                _account,
                _indexToken,
                block.timestamp,
                0,
                false
            );
        }

        emit ExecuteDecreasePosition(
            _account,
            _path,
            _indexToken,
            _sizeDeltaToken,
            _isLong,
            executionFee
        );

        if (amountOutTokenAfterFees == 0) {
            return;
        }

        if (_path.length > 1) {
            _transferOut(_path[0], amountOutTokenAfterFees, vault);
            amountOutTokenAfterFees = _swap(_path, address(this), true);
        }

        //        if (request.withdrawETH) {
        //            _transferOutETH(amountOutTokenAfterFees, payable(_account));
        //            return;
        //        }

        _transferOut(
            _path[_path.length - 1],
            amountOutTokenAfterFees,
            _account
        );
    }

    function createCancelOrderRequest(
        bytes32 _key,
        uint256 _orderIdx,
        bool _isReduce
    ) external payable nonReentrant whenNotPaused {
        address account;
        address indexToken;

        if (_isReduce) {
            IFuturXGatewayStorage.DecreasePositionRequest
                memory request = _getDecreasePositionRequest(_key);
            account = request.account;
            indexToken = request.indexToken;
        } else {
            IFuturXGatewayStorage.IncreasePositionRequest
                memory request = _getIncreasePositionRequest(_key);
            account = request.account;
            indexToken = request.indexToken;
        }
        _validate(account == msg.sender, Errors.FGW_NOT_OWNER_OF_ORDER);

        _crossBlockchainCall(
            pcsId,
            pscCrossChainGateway,
            uint8(Method.CANCEL_LIMIT),
            abi.encode(
                _key,
                _indexTokenToManager(indexToken),
                _orderIdx,
                _isReduce,
                msg.sender
            )
        );
    }

    function executeCancelIncreaseOrder(
        bytes32 _key,
        bool _isReduce,
        uint256 _amountOutUsd,
        uint256 _sizeDeltaToken,
        uint256 _entryPrice,
        bool _isLong
    ) external nonReentrant {
        _validateCaller(msg.sender);

        _amountOutUsd = _amountOutUsd.mul(PRICE_DECIMALS);

        if (_isReduce) {
            _cancelReduceOrder(
                _key,
                _amountOutUsd,
                _sizeDeltaToken,
                _entryPrice,
                _isLong
            );
            return;
        }

        _cancelIncreaseOrder(
            _key,
            _amountOutUsd,
            _sizeDeltaToken,
            _entryPrice,
            _isLong
        );
    }

    function _cancelReduceOrder(
        bytes32 _key,
        uint256 _amountOutUsd,
        uint256 _sizeDeltaToken,
        uint256 _entryPrice,
        bool _isLong
    ) private {
        if (_sizeDeltaToken == 0 || _amountOutUsd == 0) {
            _deleteDecreasePositionRequest(_key);
            return;
        }

        IFuturXGatewayStorage.DecreasePositionRequest
            memory request = _getDeleteDecreasePositionRequest(_key);

        _executeDecreasePosition(
            request.account,
            request.path,
            request.indexToken,
            _amountOutUsd,
            0,
            _entryPrice,
            _sizeDeltaToken,
            _isLong
        );
    }

    function _cancelIncreaseOrder(
        bytes32 _key,
        uint256 _amountOutUsd,
        uint256 _sizeDeltaToken,
        uint256 _entryPrice,
        bool _isLong
    ) private {
        IFuturXGatewayStorage.IncreasePositionRequest
            memory request = _getDeleteIncreasePositionRequest(_key);

        _updatePendingCollateral(
            request.account,
            request.indexToken,
            request.path[request.path.length - 1],
            2
        );

        if (_sizeDeltaToken == 0) {
            _transferOut(
                request.path[0],
                request.amountInToken,
                request.account
            );
            if (request.voucherId > 0) {
                _refundVoucher(request.voucherId, request.account);
            }
            return;
        }

        if (_amountOutUsd == 0) {
            return;
        }

        uint256 amountOutToken = IVault(vault).usdToTokenMin(
            request.path[0],
            _amountOutUsd
        );

        if (amountOutToken > request.amountInToken) {
            // TODO: Position already partially filled, however withdraw
            // TODO: amount is greater than deposited amount due to price change?
            amountOutToken = request.amountInToken;
            return;
        }

        _transferOut(request.path[0], amountOutToken, request.account);

        uint256 remainingAmountToken = request.amountInToken.sub(
            amountOutToken
        );
        _executeIncreasePosition(
            request.account,
            request.path,
            request.indexToken,
            remainingAmountToken,
            0,
            _entryPrice,
            _sizeDeltaToken,
            _isLong,
            0
        );
    }

    function liquidatePosition(
        address _trader,
        address _collateralToken,
        address _indexToken,
        uint256 _positionSize,
        uint256 _positionMargin,
        bool _isLong
    ) public nonReentrant {
        _validateCaller(msg.sender);
        IVault(vault).liquidatePosition(
            _trader,
            _collateralToken,
            _indexToken,
            _positionSize,
            _positionMargin,
            _isLong
        );
    }

    function createAddCollateralRequest(
        address[] memory _path,
        address _indexToken,
        uint256 _amountInToken,
        bool _isLong
    ) external nonReentrant whenNotPaused {
        address paidToken = _path[0];
        address collateralToken = _path[_path.length - 1];

        _validateUpdateCollateral(
            msg.sender,
            collateralToken,
            _indexToken,
            _isLong
        );

        _amountInToken = _adjustDecimalToToken(paidToken, _amountInToken);
        _transferIn(paidToken, _amountInToken);

        uint256 swapFeeToken = paidToken == collateralToken
            ? 0
            : IGatewayUtils(gatewayUtils).getSwapFee(_path, _amountInToken);

        (, bytes32 requestKey) = _storeUpdateCollateralRequest(
            _path,
            _indexToken,
            _amountInToken,
            _isLong,
            swapFeeToken
        );

        uint256 swapFeeUsd = _tokenToUsdMin(collateralToken, swapFeeToken);
        uint256 amountInUsd = _tokenToUsdMin(paidToken, _amountInToken).sub(
            swapFeeUsd
        );

        _crossBlockchainCall(
            pcsId,
            pscCrossChainGateway,
            uint8(Method.ADD_MARGIN),
            abi.encode(
                requestKey,
                _indexTokenToManager(_indexToken),
                amountInUsd.div(PRICE_DECIMALS),
                msg.sender
            )
        );

        emit CollateralAddCreated(
            requestKey,
            msg.sender,
            paidToken,
            _amountInToken,
            amountInUsd,
            swapFeeUsd
        );
    }

    function executeAddCollateral(bytes32 _key) external nonReentrant {
        _validateCaller(msg.sender);

        IFuturXGatewayStorage.UpdateCollateralRequest
            memory request = _getDeleteUpdateCollateralRequest(_key);

        address paidToken = request.path[0];
        address collateralToken = request.path[request.path.length - 1];

        if (request.amountInToken == 0) {
            return;
        }

        uint256 amountInToken = request.amountInToken;

        if (request.path.length > 1) {
            _transferOut(paidToken, amountInToken, vault);
            amountInToken = _swap(request.path, address(this), false);
        }

        _transferOut(collateralToken, amountInToken, vault);

        IVault(vault).addCollateral(
            request.account,
            request.path,
            request.indexToken,
            request.isLong,
            request.feeToken
        );
        //        emit CollateralAdded(request.account, collateralToken, amountInToken);
    }

    function createRemoveCollateralRequest(
        address[] memory _path,
        address _indexToken,
        uint256 _amountOutUsd,
        bool _isLong
    ) external nonReentrant whenNotPaused {
        address collateralToken = _path[0];

        _validateUpdateCollateral(
            msg.sender,
            collateralToken,
            _indexToken,
            _isLong
        );

        uint256 amountOutUsdFormatted = _amountOutUsd.mul(PRICE_DECIMALS);
        uint256 amountOutToken = _usdToTokenMin(
            collateralToken,
            amountOutUsdFormatted
        );
        (, bytes32 requestKey) = _storeUpdateCollateralRequest(
            _path,
            _indexToken,
            amountOutToken,
            _isLong,
            0
        );

        _crossBlockchainCall(
            pcsId,
            pscCrossChainGateway,
            uint8(Method.REMOVE_MARGIN),
            abi.encode(
                requestKey,
                _indexTokenToManager(_indexToken),
                _amountOutUsd,
                msg.sender
            )
        );
        emit CollateralRemoveCreated(
            requestKey,
            msg.sender,
            collateralToken,
            amountOutToken,
            amountOutUsdFormatted
        );
    }

    function executeRemoveCollateral(
        bytes32 _key,
        uint256 _amountOutUsd
    ) external nonReentrant {
        _validateCaller(msg.sender);

        IFuturXGatewayStorage.UpdateCollateralRequest
            memory request = _getDeleteUpdateCollateralRequest(_key);

        if (_amountOutUsd == 0) {
            return;
        }

        address collateralToken = request.path[0];
        address receiveToken = request.path[request.path.length - 1];

        _amountOutUsd = _amountOutUsd.mul(PRICE_DECIMALS);
        uint256 amountOutToken = _usdToTokenMin(collateralToken, _amountOutUsd);

        IVault(vault).removeCollateral(
            request.account,
            collateralToken,
            request.indexToken,
            request.isLong,
            amountOutToken
        );

        if (request.path.length > 1) {
            _transferOut(collateralToken, amountOutToken, vault);
            amountOutToken = _swap(request.path, address(this), true);
        }

        _transferOut(receiveToken, amountOutToken, request.account);
        //        emit CollateralRemove(request.account, receiveToken, amountOutToken);
    }

    function triggerTPSL(
        address _account,
        address _positionManager,
        uint256 _amountOutUsdAfterFees,
        uint256 _feeUsd,
        uint256 _sizeDeltaInToken,
        bool _isHigherPrice,
        bool _isLong
    ) external {
        //        _validateCaller(msg.sender);
        //
        //        address indexToken = indexTokens[_positionManager];
        //        bytes32 triggeredTPSLKey = _getTPSLRequestKey(
        //            _account,
        //            indexToken,
        //            _isHigherPrice
        //        );
        //        executeDecreasePosition(
        //            TPSLRequestMap[triggeredTPSLKey],
        //            _amountOutUsdAfterFees,
        //            _feeUsd,
        //            0, // TODO: Add _entryPip
        //            _sizeDeltaInToken,
        //            _isLong
        //        );
        //        _deleteDecreasePositionRequests(
        //            TPSLRequestMap[
        //                _getTPSLRequestKey(_account, indexToken, !_isHigherPrice)
        //            ]
        //        );
        //        _deleteTPSLRequestMap(
        //            _getTPSLRequestKey(_account, indexToken, !_isHigherPrice)
        //        );
        //        _deleteDecreasePositionRequests(TPSLRequestMap[triggeredTPSLKey]);
        //        _deleteTPSLRequestMap(triggeredTPSLKey);
    }

    function executeClaimFund(
        address _manager,
        address _account,
        bool _isLong,
        uint256 _amountOutUsd
    ) external nonReentrant {
        _validateCaller(msg.sender);

        _amountOutUsd = _amountOutUsd * PRICE_DECIMALS;

        address indexToken = _managerToIndexToken(_manager);
        _validate(
            indexToken != address(0),
            Errors.FGW_INDEX_TOKEN_MUST_NOT_BE_EMPTY
        );

        bytes32 key = getPositionKey(_account, indexToken, _isLong);
        address collateralToken = latestExecutedCollateral[key];
        _validate(
            collateralToken != address(0),
            Errors.FGW_COLLATERAL_MUST_NOT_BE_EMPTY
        );

        delete latestExecutedCollateral[key];

        uint256 amountOutToken = IVault(vault).claimFund(
            collateralToken,
            _account,
            _isLong,
            _amountOutUsd,
            address(this)
        );
        _transferOut(collateralToken, amountOutToken, _account);
    }

    function refund(
        bytes32 _key,
        Method _method
    ) external payable nonReentrant {
        _validateCaller(msg.sender);

        if (_method == Method.OPEN_LIMIT || _method == Method.OPEN_MARKET) {
            if (_method == Method.OPEN_MARKET) {
                // Fire clear pending update position request in process chain
                _crossBlockchainCall(
                    pcsId,
                    pscCrossChainGateway,
                    uint8(Method.EXECUTE_STORE_POSITION),
                    abi.encode(
                        _key,
                        // Singal 1 is to clear
                        1
                    )
                );
            }

            IFuturXGatewayStorage.IncreasePositionRequest
                memory request = _getDeleteIncreasePositionRequest(_key);

            _updatePendingCollateral(
                request.account,
                request.indexToken,
                request.path[request.path.length - 1],
                2
            );

            _transferOut(
                request.path[0],
                request.amountInToken,
                request.account
            );
            if (request.voucherId > 0) {
                _refundVoucher(request.voucherId, request.account);
            }
        }
        if (_method == Method.ADD_MARGIN) {
            IFuturXGatewayStorage.UpdateCollateralRequest
                memory request = _getDeleteUpdateCollateralRequest(_key);
            _transferOut(
                request.path[0],
                request.amountInToken,
                request.account
            );
        }
    }

    function _increasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _entryPrice,
        uint256 _sizeDeltaToken,
        bool _isLong,
        uint256 _feeUsd
    ) internal {
        //        if (!_isLong && _sizeDelta > 0) {
        //            uint256 markPrice = _isLong
        //                ? IVault(vault).getMaxPrice(_indexToken)
        //                : IVault(vault).getMinPrice(_indexToken);
        //            // should be called strictly before position is updated in Vault
        //            IShortsTracker(shortsTracker).updateGlobalShortData(
        //                _indexToken,
        //                _sizeDelta,
        //                markPrice,
        //                true
        //            );
        //        }

        IVault(vault).increasePosition(
            _account,
            _collateralToken,
            _indexToken,
            _entryPrice,
            _sizeDeltaToken,
            _isLong,
            _feeUsd
        );
    }

    function _decreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _entryPrice,
        uint256 _sizeDeltaToken,
        bool _isLong,
        address _receiver,
        uint256 _amountOutUsd,
        uint256 _feeUsd
    ) internal returns (uint256) {
        //        if (!_isLong && _sizeDelta > 0) {
        //            uint256 markPrice = _isLong
        //                ? IVault(vault).getMinPrice(_indexToken)
        //                : IVault(vault).getMaxPrice(_indexToken);
        //
        //            // should be called strictly before position is updated in Vault
        //            IShortsTracker(shortsTracker).updateGlobalShortData(
        //                _indexToken,
        //                _sizeDelta,
        //                markPrice,
        //                false
        //            );
        //        }

        return
            IVault(vault).decreasePosition(
                _account,
                _collateralToken,
                _indexToken,
                _entryPrice,
                _sizeDeltaToken,
                _isLong,
                _receiver,
                _amountOutUsd,
                _feeUsd
            );
    }

    function _createIncreasePosition(
        CreateIncreasePositionParam memory param
    ) internal returns (bytes32) {
        (, bytes32 requestKey) = _storeIncreasePositionRequest(param);

        {
            uint256 sizeDeltaToken = param.sizeDeltaToken;
            uint256 pip = param.pip;
            uint16 leverage = param.leverage;
            bool isLong = param.isLong;
            uint256 amountInUsd = param.amountInUsd;
            if (param.pip > 0) {
                _crossBlockchainCall(
                    pcsId,
                    pscCrossChainGateway,
                    uint8(Method.OPEN_LIMIT),
                    abi.encode(
                        requestKey,
                        _indexTokenToManager(param.indexToken),
                        isLong,
                        sizeDeltaToken,
                        pip,
                        leverage,
                        msg.sender,
                        amountInUsd
                    )
                );
            } else {
                _crossBlockchainCall(
                    pcsId,
                    pscCrossChainGateway,
                    uint8(Method.OPEN_MARKET),
                    abi.encode(
                        requestKey,
                        _indexTokenToManager(param.indexToken),
                        isLong,
                        sizeDeltaToken,
                        leverage,
                        msg.sender,
                        amountInUsd
                    )
                );
            }
        }

        emit CreateIncreasePosition(
            param.account,
            param.path,
            param.indexToken,
            param.amountInAfterFeeToken,
            param.sizeDeltaToken,
            param.pip,
            param.isLong,
            param.feeInUsd,
            requestKey
        );

        return requestKey;
    }

    function _createDecreasePosition(
        address _account,
        address[] memory _path,
        address _indexToken,
        uint256 _pip,
        uint256 _sizeDeltaToken,
        bool _isLong,
        bool _withdrawETH
    ) internal returns (bytes32) {
        (, bytes32 requestKey) = _storeDecreasePositionRequest(
            _account,
            _path,
            _indexToken,
            _withdrawETH,
            _sizeDeltaToken
        );

        if (_pip == 0) {
            _crossBlockchainCall(
                pcsId,
                pscCrossChainGateway,
                uint8(Method.CLOSE_POSITION),
                abi.encode(
                    requestKey,
                    _indexTokenToManager(_indexToken),
                    _sizeDeltaToken,
                    msg.sender
                )
            );
        } else {
            _crossBlockchainCall(
                pcsId,
                pscCrossChainGateway,
                uint8(Method.CLOSE_LIMIT_POSITION),
                abi.encode(
                    requestKey,
                    _indexTokenToManager(_indexToken),
                    _pip,
                    _sizeDeltaToken,
                    msg.sender
                )
            );
        }

        emit CreateDecreasePosition(
            _account,
            _path,
            _indexToken,
            _pip,
            _sizeDeltaToken,
            _isLong,
            executionFee,
            requestKey,
            block.number,
            block.timestamp
        );
        return requestKey;
    }

    function _applyVoucher(uint256 _voucherId) private {
        _transferInVoucher(_voucherId);
        IFuturXVoucher(futurXVoucher).deactivate(_voucherId);
    }

    function _refundVoucher(uint256 _voucherId, address _account) private {
        _transferOutVoucher(_voucherId, _account);
        IFuturXVoucher(futurXVoucher).reActivate(_voucherId);
        emit VoucherRefunded(_voucherId, _account);
    }

    function _collectFees(
        address _account,
        address[] memory _path,
        address _indexToken,
        uint256 _amountInToken,
        uint256 _amountInUsd,
        uint16 _leverage,
        bool _isLong,
        bool _isLimitOrder
    ) internal returns (uint256 positionFeeUsd, uint256 totalFeeUsd) {
        {
            uint256 swapFeeUsd;
            (positionFeeUsd, swapFeeUsd, totalFeeUsd) = IGatewayUtils(
                gatewayUtils
            ).calculateMarginFees(
                    _account,
                    _path,
                    _indexToken,
                    _isLong,
                    _amountInToken,
                    _amountInUsd,
                    _leverage,
                    _isLimitOrder
                );
            emit CollectFees(
                _amountInToken,
                positionFeeUsd,
                0,
                swapFeeUsd,
                block.timestamp
            );
        }
        return (positionFeeUsd, totalFeeUsd);
    }

    function _storeIncreasePositionRequest(
        CreateIncreasePositionParam memory param
    ) internal returns (uint256, bytes32) {
        return
            IFuturXGatewayStorage(gatewayStorage).storeIncreasePositionRequest(
                IFuturXGatewayStorage.IncreasePositionRequest(
                    param.account,
                    param.path,
                    param.indexToken,
                    param.hasCollateralInETH,
                    param.amountInAfterFeeToken,
                    param.feeInUsd,
                    param.positionFeeUsd,
                    param.voucherId
                )
            );
    }

    function _getIncreasePositionRequest(
        bytes32 _key
    ) internal returns (IFuturXGatewayStorage.IncreasePositionRequest memory) {
        return
            IFuturXGatewayStorage(gatewayStorage).getIncreasePositionRequest(
                _key
            );
    }

    function _getDeleteIncreasePositionRequest(
        bytes32 _key
    ) internal returns (IFuturXGatewayStorage.IncreasePositionRequest memory) {
        return
            IFuturXGatewayStorage(gatewayStorage)
                .getDeleteIncreasePositionRequest(_key);
    }

    function _storeDecreasePositionRequest(
        address _account,
        address[] memory _path,
        address _indexToken,
        bool _withdrawETH,
        uint256 _sizeDeltaToken
    ) internal returns (uint256, bytes32) {
        return
            IFuturXGatewayStorage(gatewayStorage).storeDecreasePositionRequest(
                IFuturXGatewayStorage.DecreasePositionRequest(
                    _account,
                    _path,
                    _indexToken,
                    _withdrawETH,
                    _sizeDeltaToken
                )
            );
    }

    function _getDecreasePositionRequest(
        bytes32 _key
    ) internal returns (IFuturXGatewayStorage.DecreasePositionRequest memory) {
        return
            IFuturXGatewayStorage(gatewayStorage).getDecreasePositionRequest(
                _key
            );
    }

    function _getDeleteDecreasePositionRequest(
        bytes32 _key
    ) internal returns (IFuturXGatewayStorage.DecreasePositionRequest memory) {
        return
            IFuturXGatewayStorage(gatewayStorage)
                .getDeleteDecreasePositionRequest(_key);
    }

    function _deleteDecreasePositionRequest(bytes32 _key) internal {
        IFuturXGatewayStorage(gatewayStorage).deleteDecreasePositionRequest(
            _key
        );
    }

    function _storeUpdateCollateralRequest(
        address[] memory _path,
        address _indexToken,
        uint256 _amountInToken,
        bool _isLong,
        uint256 _swapFeeToken
    ) internal returns (uint256, bytes32) {
        return
            IFuturXGatewayStorage(gatewayStorage).storeUpdateCollateralRequest(
                IFuturXGatewayStorage.UpdateCollateralRequest(
                    msg.sender,
                    _path,
                    _indexToken,
                    _amountInToken,
                    _isLong,
                    _swapFeeToken
                )
            );
    }

    function _getDeleteUpdateCollateralRequest(
        bytes32 _key
    ) internal returns (IFuturXGatewayStorage.UpdateCollateralRequest memory) {
        return
            IFuturXGatewayStorage(gatewayStorage)
                .getDeleteUpdateCollateralRequest(_key);
    }

    function _transferIn(address _token, uint256 _tokenAmount) internal {
        if (_tokenAmount == 0) {
            return;
        }
        IERC20Upgradeable(_token).safeTransferFrom(
            msg.sender,
            address(this),
            _tokenAmount
        );
    }

    function _transferInVoucher(uint256 _voucherId) internal {
        IERC721Upgradeable(futurXVoucher).safeTransferFrom(
            msg.sender,
            address(this),
            _voucherId
        );
    }

    function _transferInETH() internal {
        if (msg.value != 0) {
            IWETH(weth).deposit{value: msg.value}();
        }
    }

    function _transferOut(
        address _token,
        uint256 _tokenAmount,
        address _account
    ) internal {
        if (_tokenAmount == 0) {
            return;
        }
        IERC20Upgradeable(_token).safeTransfer(payable(_account), _tokenAmount);
    }

    function _transferOutVoucher(
        uint256 _voucherId,
        address _account
    ) internal {
        IERC721Upgradeable(futurXVoucher).safeTransferFrom(
            address(this),
            _account,
            _voucherId
        );
    }

    function _transferOutETH(
        uint256 _amountOut,
        address payable _account
    ) internal {
        if (_amountOut > 0) {
            IWETH(weth).transfer(_account, _amountOut);
        }
    }

    function _adjustDecimalToToken(
        address _token,
        uint256 _tokenAmount
    ) internal view returns (uint256) {
        return IVault(vault).adjustDecimalToToken(_token, _tokenAmount);
    }

    function _validateIncreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _amountInUsd,
        uint256 _sizeDeltaToken,
        uint256 _pip,
        uint16 _leverage,
        bool _isLong,
        uint256 _voucherId
    ) private {
        IGatewayUtils(gatewayUtils).validateIncreasePosition(
            msg.sender,
            msg.value,
            _path,
            _indexToken,
            _amountInUsd,
            _sizeDeltaToken,
            _pip,
            _leverage,
            _isLong,
            _voucherId
        );
    }

    function _validateUpdateCollateral(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) private {
        IGatewayUtils(gatewayUtils).validateUpdateCollateral(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
    }

    function _validateCaller(address _account) private {
        _validate(positionKeepers[_account], Errors.FGW_CALLER_NOT_WHITELISTED);
    }

    function _usdToTokenMin(
        address _token,
        uint256 _usdAmount
    ) private view returns (uint256) {
        return IVault(vault).usdToTokenMin(_token, _usdAmount);
    }

    function _tokenToUsdMin(
        address _token,
        uint256 _tokenAmount
    ) private view returns (uint256) {
        return IVault(vault).tokenToUsdMin(_token, _tokenAmount);
    }

    /// @dev This function is used to execute the cross blockchain call to update position call
    function _executeExecuteUpdatePositionData(bytes32 _requestKey) private {
        _crossBlockchainCall(
            pcsId,
            pscCrossChainGateway,
            uint8(Method.EXECUTE_STORE_POSITION),
            abi.encode(_requestKey, uint8(0))
        );
    }

    function _updateLatestExecutedCollateral(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) private {
        bytes32 key = getPositionKey(_account, _indexToken, _isLong);
        latestExecutedCollateral[key] = _collateralToken;
    }

    function _updatePendingCollateral(
        address _account,
        address _indexToken,
        address _collateralToken,
        uint8 _op
    ) private {
        IFuturXGatewayStorage.UpPendingCollateralParam
            memory params = IFuturXGatewayStorage.UpPendingCollateralParam(
                _account,
                _indexToken,
                _collateralToken,
                _op
            );
        IFuturXGatewayStorage(gatewayStorage).updatePendingCollateral(params);
    }

    function _crossBlockchainCall(
        uint256 _bcId,
        address _contract,
        uint8 _destMethodID,
        bytes memory _functionCallData
    ) internal {
        CrosschainFunctionCallInterface(futuresAdapter).crossBlockchainCall(
            _bcId,
            _contract,
            _destMethodID,
            _functionCallData
        );
    }

    function getPositionKey(
        address _account,
        address _indexToken,
        bool _isLong
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _indexToken, _isLong));
    }

    function _indexTokenToManager(
        address _indexToken
    ) internal view returns (address) {
        return coreManagers[_indexToken];
    }

    function _managerToIndexToken(
        address _manager
    ) internal view returns (address) {
        return indexTokens[_manager];
    }

    function _swap(
        address[] memory _path,
        address _receiver,
        bool _shouldCollectFee
    ) internal returns (uint256) {
        _validate(_path.length == 2, Errors.FGW_INVALID_PATH_LENGTH);

        if (_shouldCollectFee) {
            return IVault(vault).swap(_path[0], _path[1], _receiver);
        }
        return IVault(vault).swapWithoutFees(_path[0], _path[1], _receiver);
    }

    /**
     * @dev See {IERC721Receiver-onERC721Received}.
     *
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    event GovernanceLogicChanged(address _prev, address _new);

    /// @notice Set the governance logic contract
    /// Only owner can call this function
    /// @dev This function is used to set the governance logic contract
    /// @param _newGovernanceLogic The new governance logic contract
    function setGovernanceLogic(
        address _newGovernanceLogic
    ) external onlyOwner {
        StorageSlotUpgradeable
            .getAddressSlot(_GOVERNANCE_LOGIC_CONTRACT_SLOT_)
            .value = _newGovernanceLogic;
        emit GovernanceLogicChanged(
            StorageSlotUpgradeable
                .getAddressSlot(_GOVERNANCE_LOGIC_CONTRACT_SLOT_)
                .value,
            _newGovernanceLogic
        );
    }

    /// @notice Execute a governance function
    /// Only owner can call this function
    /// @dev This function is used to execute a governance function in the governance logic contract using delegatecall to save contract size
    /// @param _data The data to execute the function (you need to encode data yourself)
    function executeGovFunction(bytes memory _data) external onlyOwner {
        address _target = StorageSlotUpgradeable
            .getAddressSlot(_GOVERNANCE_LOGIC_CONTRACT_SLOT_)
            .value;
        (bool success, bytes memory returnData) = _target.delegatecall(_data);
        require(success, string(returnData));
    }

    //    function pause() external onlyOwner {
    //        _pause();
    //    }
    //
    //    function unpause() external onlyOwner {
    //        _unpause();
    //    }

    function _validate(bool _condition, string memory _errorCode) private view {
        require(_condition, _errorCode);
    }
}
