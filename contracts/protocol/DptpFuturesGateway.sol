// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import "@positionex/position-helper/contracts/utils/Require.sol";
import "../interfaces/CrosschainFunctionCallInterface.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IVaultUtils.sol";
import "../interfaces/IShortsTracker.sol";
import "../interfaces/IGatewayUtils.sol";
import "../token/interface/IWETH.sol";
import {Errors} from "./libraries/helpers/Errors.sol";
import "../interfaces/IFuturXGateway.sol";

contract DptpFuturesGateway is
    PausableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    IFuturXGateway
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;
    using SafeCastUpgradeable for uint256;
    using AddressUpgradeable for address;

    uint256 constant PRICE_DECIMALS = 10**12;
    uint256 constant WEI_DECIMALS = 10**18;

    enum SetTPSLOption {
        BOTH,
        ONLY_HIGHER,
        ONLY_LOWER
    }

    enum Method {
        OPEN_MARKET,
        OPEN_LIMIT,
        CANCEL_LIMIT,
        ADD_MARGIN,
        REMOVE_MARGIN,
        CLOSE_POSITION,
        INSTANTLY_CLOSE_POSITION,
        CLOSE_LIMIT_POSITION,
        CLAIM_FUND,
        SET_TPSL,
        UNSET_TP_AND_SL,
        UNSET_TP_OR_SL,
        OPEN_MARKET_BY_QUOTE,
        EXECUTE_STORE_POSITION
    }

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
        uint256 sizeDelta,
        bool isLong,
        uint256 feeUsd
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
        uint256 swapFee
    );

    event CollateralAdded(address account, address token, uint256 tokenAmount);
    event CollateralRemove(address account, address token, uint256 tokenAmount);

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

    struct IncreasePositionRequest {
        address account;
        address[] path;
        address indexToken;
        bool hasCollateralInETH;
        uint256 amountInToken;
        uint256 feeUsd;
    }

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
    }

    struct AddCollateralRequest {
        address account;
        address[] path;
        address indexToken;
        uint256 amountInToken;
        bool isLong;
        uint256 feeToken;
    }

    uint256 public pcsId;
    address public pscCrossChainGateway;

    address public futuresAdapter;
    address public vault;
    address public shortsTracker;
    address public weth;
    address public gatewayUtils;

    mapping(address => bool) public positionKeepers;

    mapping(address => uint256) public increasePositionsIndex;
    mapping(bytes32 => IncreasePositionRequest) public increasePositionRequests;

    mapping(address => uint256) public decreasePositionsIndex;
    mapping(bytes32 => DecreasePositionRequest) public decreasePositionRequests;

    mapping(address => uint256) public override maxGlobalLongSizes;
    mapping(address => uint256) public override maxGlobalShortSizes;

    bytes32[] public increasePositionRequestKeys;
    bytes32[] public decreasePositionRequestKeys;

    uint256 public maxTimeDelay;
    uint256 public override executionFee;

    // mapping indexToken with positionManager
    mapping(address => address) public coreManagers;
    // mapping positionManager with indexToken
    mapping(address => address) public indexTokens;
    mapping(bytes32 => bytes32) public TPSLRequestMap;

    mapping(address => uint256) public addCollateralIndex;
    mapping(bytes32 => AddCollateralRequest) public addCollateralRequests;
    bytes32[] public addCollateralRequestKeys;

    function initialize(
        uint256 _pcsId,
        address _pscCrossChainGateway,
        address _futuresAdapter,
        address _vault,
        address _weth,
        address _gatewayUtils,
        uint256 _executionFee
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
        __Pausable_init();

        pcsId = _pcsId;

        //        require(_pscCrossChainGateway != address(0), Errors.VL_EMPTY_ADDRESS);
        Require._require(
            _pscCrossChainGateway != address(0),
            Errors.VL_EMPTY_ADDRESS
        );

        pscCrossChainGateway = _pscCrossChainGateway;

        //        require(_futuresAdapter != address(0), Errors.VL_EMPTY_ADDRESS);
        Require._require(
            _futuresAdapter != address(0),
            Errors.VL_EMPTY_ADDRESS
        );

        futuresAdapter = _futuresAdapter;

        //        require(_vault != address(0), Errors.VL_EMPTY_ADDRESS);
        Require._require(_vault != address(0), Errors.VL_EMPTY_ADDRESS);

        vault = _vault;

        //        require(_weth != address(0), Errors.VL_EMPTY_ADDRESS);
        Require._require(_weth != address(0), Errors.VL_EMPTY_ADDRESS);
        weth = _weth;

        require(_gatewayUtils != address(0), Errors.VL_EMPTY_ADDRESS);
        gatewayUtils = _gatewayUtils;

        executionFee = _executionFee;
    }

    function createIncreasePositionRequest(
        address[] memory _path,
        address _indexToken,
        uint256 _amountInUsd,
        uint256 _sizeDeltaToken,
        uint16 _leverage,
        bool _isLong
    ) external payable nonReentrant whenNotPaused returns (bytes32) {
        IGatewayUtils(gatewayUtils).validateIncreasePosition(
            msg.sender,
            msg.value,
            _path,
            _indexToken,
            _sizeDeltaToken,
            _leverage,
            _isLong
        );
        _updateLatestIncreasePendingCollateral(
            msg.sender,
            _path[_path.length - 1],
            _indexToken,
            _isLong
        );

        _amountInUsd = _amountInUsd.mul(PRICE_DECIMALS);
        uint256 amountInToken = _usdToTokenMin(_path[0], _amountInUsd);

        uint256 totalFeeUsd = _collectFees(
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
            _amountInUsd.add(totalFeeUsd)
        );

        _transferIn(_path[0], amountInAfterFeeToken);
        _transferInETH();

        CreateIncreasePositionParam memory params = CreateIncreasePositionParam(
            msg.sender,
            _path,
            _indexToken,
            amountInAfterFeeToken,
            _amountInUsd,
            totalFeeUsd,
            _sizeDeltaToken,
            0,
            _leverage,
            _isLong,
            false
        );
        return _createIncreasePosition(params);
    }

    function createIncreasePositionETH(
        address[] memory _path,
        address _indexToken,
        uint256 _amountInUsd,
        uint256 _sizeDeltaToken,
        uint16 _leverage,
        bool _isLong
    ) external payable nonReentrant whenNotPaused returns (bytes32) {
        //            require(msg.value >= executionFee, "fee");
        //            require(_path.length == 1 || _path.length == 2, "len");
        //            require(_path[0] == weth, "path");
        //            _validateSize(_path[0], _sizeDeltaToken, false);
        //
        //            uint256 amountInToken = msg.value.sub(executionFee);
        //            _transferInETH();
        //
        //            CreateIncreasePositionParam memory params = CreateIncreasePositionParam(
        //                msg.sender,
        //                _path,
        //                _indexToken,
        //                amountInToken,
        //                _amountInUsd,
        //                _sizeDeltaToken,
        //                0,
        //                _leverage,
        //                _isLong,
        //                false
        //            );
        //            return _createIncreasePosition(params);
        return 0;
    }

    function createIncreaseOrderRequest(
        address[] memory _path,
        address _indexToken,
        uint256 _amountInUsd,
        uint256 _pip,
        uint256 _sizeDeltaToken,
        uint16 _leverage,
        bool _isLong
    ) external payable nonReentrant whenNotPaused returns (bytes32) {
        IGatewayUtils(gatewayUtils).validateIncreasePosition(
            msg.sender,
            msg.value,
            _path,
            _indexToken,
            _sizeDeltaToken,
            _leverage,
            _isLong
        );
        _updateLatestIncreasePendingCollateral(
            msg.sender,
            _path[_path.length - 1],
            _indexToken,
            _isLong
        );

        _amountInUsd = _amountInUsd.mul(PRICE_DECIMALS);
        uint256 amountInToken = _usdToTokenMin(_path[0], _amountInUsd);

        uint256 totalFeeUsd = _collectFees(
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
            _amountInUsd.add(totalFeeUsd)
        );

        _transferIn(_path[0], amountInAfterFeeToken);
        _transferInETH();

        CreateIncreasePositionParam memory params = CreateIncreasePositionParam(
            msg.sender,
            _path,
            _indexToken,
            amountInAfterFeeToken,
            _amountInUsd,
            totalFeeUsd,
            _sizeDeltaToken,
            _pip,
            _leverage,
            _isLong,
            false
        );

        return _createIncreasePosition(params);
    }

    function createIncreaseOrderRequestETH(
        address[] memory _path,
        address _indexToken,
        uint256 _amountInUsd,
        uint256 _pip,
        uint256 _sizeDeltaToken,
        uint16 _leverage,
        bool _isLong
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
            Require._require(_path[_path.length - 1] == weth, "path");
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
            Require._require(_path[_path.length - 1] == weth, "path");
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
        bool _isLong
    ) public nonReentrant {
        _validateCaller(msg.sender);

        IncreasePositionRequest memory request = increasePositionRequests[_key];
        Require._require(request.account != address(0), "404");

        _deleteIncreasePositionRequests(_key);

        _executeIncreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.amountInToken,
            request.feeUsd,
            _entryPrice,
            _sizeDeltaInToken,
            _isLong
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

        IncreasePositionRequest memory request = increasePositionRequests[_key];
        Require._require(request.account != address(0), "404");

        _deleteIncreasePositionRequests(_key);

        _executeIncreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.amountInToken,
            request.feeUsd,
            _entryPrice,
            _sizeDeltaInToken,
            _isLong
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
        bool _isLong
    ) internal {
        if (_amountInToken > 0) {
            address collateralToken = _path[_path.length - 1];
            uint256 amountInToken = uint256(_amountInToken);

            if (_path.length > 1) {
                _transferOut(_path[0], amountInToken, vault);
                amountInToken = _swap(_path, address(this), false);
            }

            _transferOut(collateralToken, amountInToken, vault);
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
            _sizeDeltaInToken,
            _isLong,
            _feeUsd
        );
    }

    function executeDecreasePosition(
        bytes32 _key,
        uint256 _amountOutAfterFeesUsd,
        uint256 _feeUsd,
        uint256 _entryPrice,
        uint256 _sizeDeltaToken,
        bool _isLong
    ) public nonReentrant {
        _validateCaller(msg.sender);

        DecreasePositionRequest memory request = decreasePositionRequests[_key];
        Require._require(request.account != address(0), "404");

        _deleteDecreasePositionRequests(_key);

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
            _amountOutAfterFeesUsd.mul(PRICE_DECIMALS),
            _feeUsd.mul(PRICE_DECIMALS)
        );

        _transferOutETH(executionFee, payable(msg.sender));

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
        address collateralToken;

        if (_isReduce) {
            DecreasePositionRequest memory request = decreasePositionRequests[
                _key
            ];
            account = request.account;
            collateralToken = request.path[0];
        } else {
            IncreasePositionRequest memory request = increasePositionRequests[
                _key
            ];
            account = request.account;
            collateralToken = request.path[0];
        }
        //        require(account == msg.sender, "403");
        Require._require(account == msg.sender, "403");

        _crossBlockchainCall(
            pcsId,
            pscCrossChainGateway,
            uint8(Method.CANCEL_LIMIT),
            abi.encode(
                _key,
                coreManagers[collateralToken],
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
    ) external payable nonReentrant {
        _validateCaller(msg.sender);

        if (_isReduce) {
            if (_sizeDeltaToken == 0) {
                _deleteDecreasePositionRequests(_key);
                return;
            }

            if (_amountOutUsd == 0) {
                return;
            }

            DecreasePositionRequest memory request = decreasePositionRequests[
                _key
            ];
            Require._require(request.account != address(0), "404");

            _deleteDecreasePositionRequests(_key);

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

            return;
        }

        IncreasePositionRequest memory request = increasePositionRequests[_key];
        Require._require(request.account != address(0), "404");

        _deleteIncreasePositionRequests(_key);

        if (_sizeDeltaToken == 0) {
            _transferOut(
                request.path[0],
                request.amountInToken,
                request.account
            );
            return;
        }

        if (_amountOutUsd == 0) {
            return;
        }

        uint256 amountOutToken = IVault(vault).usdToTokenMin(
            request.path[0],
            _amountOutUsd
        );

        if (amountOutToken >= request.amountInToken) {
            // TODO: Position already partially filled, however withdraw
            // TODO: amount is greater than deposited amount due to price change?
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
            _isLong
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

        bytes32 requestKey;
        uint256 swapFeeUsd;
        if (paidToken != collateralToken) {
            uint256 swapFee = IGatewayUtils(gatewayUtils).getSwapFee(
                _path,
                _amountInToken
            );
            AddCollateralRequest memory request = AddCollateralRequest(
                msg.sender,
                _path,
                _indexToken,
                _amountInToken,
                _isLong,
                swapFee
            );
            (, requestKey) = _storeAddCollateralRequest(request);

            swapFeeUsd = _tokenToUsdMin(collateralToken, swapFee);
        }

        uint256 amountInUsd = _tokenToUsdMin(paidToken, _amountInToken).sub(
            swapFeeUsd
        );

        _crossBlockchainCall(
            pcsId,
            pscCrossChainGateway,
            uint8(Method.ADD_MARGIN),
            abi.encode(
                requestKey,
                coreManagers[_indexToken],
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

        AddCollateralRequest memory request = addCollateralRequests[_key];
        Require._require(request.account != address(0), "404");

        _deleteAddCollateralRequests(_key);

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
        emit CollateralAdded(request.account, collateralToken, amountInToken);
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
        AddCollateralRequest memory request = AddCollateralRequest(
            msg.sender,
            _path,
            _indexToken,
            amountOutToken,
            _isLong,
            0
        );
        (, bytes32 requestKey) = _storeAddCollateralRequest(request);

        _crossBlockchainCall(
            pcsId,
            pscCrossChainGateway,
            uint8(Method.REMOVE_MARGIN),
            abi.encode(
                requestKey,
                coreManagers[_indexToken],
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

    function executeRemoveCollateral(bytes32 _key, uint256 _amountOutUsd)
        external
        nonReentrant
    {
        _validateCaller(msg.sender);

        AddCollateralRequest memory request = addCollateralRequests[_key];
        Require._require(request.account != address(0), "404");

        _deleteAddCollateralRequests(_key);

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
        emit CollateralRemove(request.account, receiveToken, amountOutToken);
    }

    function setTPSL(
        address[] memory _path,
        address _indexToken,
        bool _withdrawETH,
        uint128 _higherPip,
        uint128 _lowerPip,
        SetTPSLOption _option
    ) external nonReentrant whenNotPaused {
        bytes32 requestKey = _createTPSLDecreaseOrder(
            msg.sender,
            _path,
            _indexToken,
            _withdrawETH
        );
        if (_option == SetTPSLOption.ONLY_HIGHER) {
            _setTPSLToMap(
                _getTPSLRequestKey(msg.sender, _indexToken, true),
                requestKey
            );
            //            TPSLRequestMap[
            //                _getTPSLRequestKey(msg.sender, _indexToken, true)
            //            ] = requestKey;
        } else if (_option == SetTPSLOption.ONLY_LOWER) {
            _setTPSLToMap(
                _getTPSLRequestKey(msg.sender, _indexToken, false),
                requestKey
            );
            //            TPSLRequestMap[
            //                _getTPSLRequestKey(msg.sender, _indexToken, false)
            //            ] = requestKey;
        } else if (_option == SetTPSLOption.BOTH) {
            _setTPSLToMap(
                _getTPSLRequestKey(msg.sender, _indexToken, true),
                requestKey
            );
            //            TPSLRequestMap[
            //                _getTPSLRequestKey(msg.sender, _indexToken, true)
            //            ] = requestKey;
            _setTPSLToMap(
                _getTPSLRequestKey(msg.sender, _indexToken, false),
                requestKey
            );
            //            TPSLRequestMap[
            //                _getTPSLRequestKey(msg.sender, _indexToken, false)
            //            ] = requestKey;
        }
        _crossBlockchainCall(
            pcsId,
            pscCrossChainGateway,
            uint8(Method.SET_TPSL),
            abi.encode(
                coreManagers[_indexToken],
                msg.sender,
                _higherPip,
                _lowerPip,
                uint8(_option)
            )
        );
    }

    function unsetTPAndSL(address _indexToken)
        external
        nonReentrant
        whenNotPaused
    {
        _deleteDecreasePositionRequests(
            TPSLRequestMap[_getTPSLRequestKey(msg.sender, _indexToken, true)]
        );
        _deleteTPSLRequestMap(
            _getTPSLRequestKey(msg.sender, _indexToken, true)
        );
        _deleteDecreasePositionRequests(
            TPSLRequestMap[_getTPSLRequestKey(msg.sender, _indexToken, false)]
        );
        _deleteTPSLRequestMap(
            _getTPSLRequestKey(msg.sender, _indexToken, false)
        );
        _crossBlockchainCall(
            pcsId,
            pscCrossChainGateway,
            uint8(Method.UNSET_TP_AND_SL),
            abi.encode(coreManagers[_indexToken], msg.sender)
        );
    }

    function unsetTPOrSL(address _indexToken, bool _isHigherPrice)
        external
        nonReentrant
        whenNotPaused
    {
        if (_isHigherPrice) {
            _deleteDecreasePositionRequests(
                TPSLRequestMap[
                    _getTPSLRequestKey(msg.sender, _indexToken, true)
                ]
            );
            _deleteTPSLRequestMap(
                _getTPSLRequestKey(msg.sender, _indexToken, true)
            );
        } else {
            _deleteDecreasePositionRequests(
                TPSLRequestMap[
                    _getTPSLRequestKey(msg.sender, _indexToken, false)
                ]
            );
            _deleteTPSLRequestMap(
                _getTPSLRequestKey(msg.sender, _indexToken, false)
            );
        }
        _crossBlockchainCall(
            pcsId,
            pscCrossChainGateway,
            uint8(Method.UNSET_TP_OR_SL),
            abi.encode(coreManagers[_indexToken], msg.sender, _isHigherPrice)
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
    ) external {
        _validateCaller(msg.sender);

        address indexToken = indexTokens[_positionManager];
        bytes32 triggeredTPSLKey = _getTPSLRequestKey(
            _account,
            indexToken,
            _isHigherPrice
        );
        executeDecreasePosition(
            TPSLRequestMap[triggeredTPSLKey],
            _amountOutUsdAfterFees,
            _feeUsd,
            0, // TODO: Add _entryPip
            _sizeDeltaInToken,
            _isLong
        );
        _deleteDecreasePositionRequests(
            TPSLRequestMap[
                _getTPSLRequestKey(_account, indexToken, !_isHigherPrice)
            ]
        );
        _deleteTPSLRequestMap(
            _getTPSLRequestKey(_account, indexToken, !_isHigherPrice)
        );
        _deleteDecreasePositionRequests(TPSLRequestMap[triggeredTPSLKey]);
        _deleteTPSLRequestMap(triggeredTPSLKey);
    }

    function executeClaimFund(
        address _manager,
        address _account,
        bool _isLong,
        uint256 _amountOutUsd
    ) external nonReentrant {
        _validateCaller(msg.sender);

        address indexToken = indexTokens[_manager];
        require(indexToken != address(0), "invalid index token");

        bytes32 key = getPositionKey(_account, indexToken, _isLong);
        address collateralToken = latestExecutedCollateral[key];
        require(collateralToken != address(0), "invalid collateral token");

        delete latestExecutedCollateral[key];

        uint256 amountOutToken = _usdToTokenMin(
            collateralToken,
            _amountOutUsd.mul(PRICE_DECIMALS)
        );
        if (amountOutToken == 0) {
            return;
        }
        IVault(vault).withdraw(collateralToken, amountOutToken, address(this));
        _transferOut(collateralToken, amountOutToken, _account);
    }

    function refund(bytes32 _key, Method _method)
        external
        payable
        nonReentrant
    {
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
            IncreasePositionRequest memory request = increasePositionRequests[
                _key
            ];
            require(request.account != address(0), "Refund: request not found");
            _deleteIncreasePositionRequests(_key);
            _transferOut(
                request.path[0],
                request.amountInToken,
                request.account
            );
        }
        if (_method == Method.ADD_MARGIN) {
            AddCollateralRequest memory request = addCollateralRequests[_key];
            require(request.account != address(0), "Refund: request not found");
            _deleteAddCollateralRequests(_key);
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

    function _createIncreasePosition(CreateIncreasePositionParam memory param)
        internal
        returns (bytes32)
    {
        IncreasePositionRequest memory request = IncreasePositionRequest(
            param.account,
            param.path,
            param.indexToken,
            param.hasCollateralInETH,
            param.amountInAfterFeeToken,
            param.feeInUsd
        );

        (, bytes32 requestKey) = _storeIncreasePositionRequest(request);

        {
            uint256 sizeDelta = param.sizeDeltaToken;
            uint256 pip = param.pip;
            uint16 leverage = param.leverage;
            bool isLong = param.isLong;
            uint256 amountUsd = param.amountInUsd;
            if (param.pip > 0) {
                _crossBlockchainCall(
                    pcsId,
                    pscCrossChainGateway,
                    uint8(Method.OPEN_LIMIT),
                    abi.encode(
                        requestKey,
                        coreManagers[request.indexToken],
                        isLong,
                        sizeDelta,
                        pip,
                        leverage,
                        msg.sender,
                        amountUsd.div(PRICE_DECIMALS)
                    )
                );
            } else {
                _crossBlockchainCall(
                    pcsId,
                    pscCrossChainGateway,
                    uint8(Method.OPEN_MARKET),
                    abi.encode(
                        requestKey,
                        coreManagers[request.indexToken],
                        isLong,
                        sizeDelta,
                        leverage,
                        msg.sender,
                        amountUsd.div(PRICE_DECIMALS)
                    )
                );
            }
        }

        emit CreateIncreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.amountInToken,
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
        DecreasePositionRequest memory request = DecreasePositionRequest(
            _account,
            _path,
            _indexToken,
            _withdrawETH
        );

        (, bytes32 requestKey) = _storeDecreasePositionRequest(request);

        if (_pip == 0) {
            _crossBlockchainCall(
                pcsId,
                pscCrossChainGateway,
                uint8(Method.CLOSE_POSITION),
                abi.encode(
                    requestKey,
                    coreManagers[request.indexToken],
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
                    coreManagers[request.indexToken],
                    _pip,
                    _sizeDeltaToken,
                    msg.sender
                )
            );
        }

        emit CreateDecreasePosition(
            request.account,
            request.path,
            request.indexToken,
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

    function _createTPSLDecreaseOrder(
        address _account,
        address[] memory _path,
        address _indexToken,
        bool _withdrawETH
    ) internal returns (bytes32) {
        DecreasePositionRequest memory request = DecreasePositionRequest(
            _account,
            _path,
            _indexToken,
            _withdrawETH
        );
        (, bytes32 requestKey) = _storeDecreasePositionRequest(request);
        return requestKey;
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
    ) internal returns (uint256) {
        (
            uint256 positionFeeUsd,
            uint256 borrowingFeeUsd,
            uint256 swapFeeUsd,
            uint256 totalFeeUsd
        ) = IGatewayUtils(gatewayUtils).calculateMarginFees(
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
            borrowingFeeUsd,
            swapFeeUsd
        );
        return totalFeeUsd;
    }

    function _storeIncreasePositionRequest(
        IncreasePositionRequest memory _request
    ) internal returns (uint256, bytes32) {
        address account = _request.account;
        uint256 index = increasePositionsIndex[account].add(1);
        increasePositionsIndex[account] = index;
        bytes32 key = getRequestKey(account, index);

        increasePositionRequests[key] = _request;
        increasePositionRequestKeys.push(key);

        return (index, key);
    }

    function _storeDecreasePositionRequest(
        DecreasePositionRequest memory _request
    ) internal returns (uint256, bytes32) {
        address account = _request.account;
        uint256 index = decreasePositionsIndex[account].add(1);
        decreasePositionsIndex[account] = index;
        bytes32 key = getRequestKey(account, index);

        decreasePositionRequests[key] = _request;
        decreasePositionRequestKeys.push(key);

        return (index, key);
    }

    function _storeAddCollateralRequest(AddCollateralRequest memory _request)
        internal
        returns (uint256, bytes32)
    {
        address account = _request.account;
        uint256 index = addCollateralIndex[account].add(1);
        addCollateralIndex[account] = index;
        bytes32 key = getRequestKey(account, index);

        addCollateralRequests[key] = _request;
        addCollateralRequestKeys.push(key);

        return (index, key);
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

    function _transferOutETH(uint256 _amountOut, address payable _account)
        internal
    {
        if (msg.value != 0) {
            IWETH(weth).transfer(_account, _amountOut);
        }
    }

    function _adjustDecimalToToken(address _token, uint256 _tokenAmount)
        internal
        view
        returns (uint256)
    {
        return IVault(vault).adjustDecimalToToken(_token, _tokenAmount);
    }

    function _validatePositionRequest(
        address[] memory _path,
        uint16 _leverage,
        bool isValidateLeverage
    ) internal {
        Require._require(msg.value == executionFee, "fee");
        Require._require(_path.length == 1 || _path.length == 2, "len");
        if (isValidateLeverage) Require._require(_leverage > 1, "min leverage");
    }

    function _validateUpdateCollateral(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) internal view returns (bool) {
        return
            IGatewayUtils(gatewayUtils).validateUpdateCollateral(
                _account,
                _collateralToken,
                _indexToken,
                _isLong
            );
    }

    function _validateCaller(address _account) internal view returns (bool) {
        Require._require(positionKeepers[_account], "403");
        return true;
    }

    function _usdToTokenMin(address _token, uint256 _usdAmount)
        internal
        view
        returns (uint256)
    {
        return IVault(vault).usdToTokenMin(_token, _usdAmount);
    }

    function _tokenToUsdMin(address _token, uint256 _tokenAmount)
        internal
        view
        returns (uint256)
    {
        return IVault(vault).tokenToUsdMin(_token, _tokenAmount);
    }

    /// @dev This function is used to execute the cross blockchain call to update position call
    function _executeExecuteUpdatePositionData(bytes32 _requestKey) internal {
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
        delete latestIncreasePendingCollateral[key];
    }

    function _updateLatestIncreasePendingCollateral(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) private {
        bytes32 key = getPositionKey(_account, _indexToken, _isLong);
        latestIncreasePendingCollateral[key] = _collateralToken;
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

    function _deleteDecreasePositionRequests(bytes32 _key) internal {
        delete decreasePositionRequests[_key];
    }

    function _deleteTPSLRequestMap(bytes32 _key) internal {
        delete TPSLRequestMap[_key];
    }

    function _deleteIncreasePositionRequests(bytes32 _key) internal {
        delete increasePositionRequests[_key];
    }

    function _deleteAddCollateralRequests(bytes32 _key) internal {
        delete addCollateralRequests[_key];
    }

    function _setTPSLToMap(bytes32 key, bytes32 value) internal {
        TPSLRequestMap[key] = value;
    }

    function getRequestKey(address _account, uint256 _index)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_account, _index));
    }

    function getLatestIncreasePendingCollateral(
        address _account,
        address _indexToken,
        bool _isLong
    ) public view override returns (address) {
        bytes32 key = getPositionKey(_account, _indexToken, _isLong);
        return latestIncreasePendingCollateral[key];
    }

    function getPositionKey(
        address _account,
        address _indexToken,
        bool _isLong
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _indexToken, _isLong));
    }

    function _getTPSLRequestKey(
        address _account,
        address _indexToken,
        bool _isHigherPip
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _indexToken, _isHigherPip));
    }

    function _swap(
        address[] memory _path,
        address _receiver,
        bool _shouldCollectFee
    ) internal returns (uint256) {
        require(_path.length == 2, "invalid _path.length");

        if (_shouldCollectFee) {
            return IVault(vault).swap(_path[0], _path[1], _receiver);
        }
        return IVault(vault).swapWithoutFees(_path[0], _path[1], _receiver);
    }

    //******************************************************************************************************************
    // ONLY OWNER FUNCTIONS
    //******************************************************************************************************************

    function setExecutionFee(uint256 _executionFee) external onlyOwner {
        executionFee = _executionFee;
    }

    function setWeth(address _weth) external onlyOwner {
        weth = _weth;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function setFuturesAdapter(address _futuresAdapter) external onlyOwner {
        futuresAdapter = _futuresAdapter;
    }

    function setPosiChainId(uint256 _posiChainId) external onlyOwner {
        pcsId = _posiChainId;
    }

    function setPosiChainCrosschainGatewayContract(address _address)
        external
        onlyOwner
    {
        pscCrossChainGateway = _address;
    }

    function setPositionKeeper(address _address) external onlyOwner {
        positionKeepers[_address] = true;
    }

    function setCoreManager(address _token, address _manager)
        external
        onlyOwner
    {
        coreManagers[_token] = _manager;
        indexTokens[_manager] = _token;
    }

    function setMaxGlobalShortSize(address _token, uint256 _amount)
        external
        onlyOwner
    {
        maxGlobalShortSizes[_token] = _amount;
    }

    function setMaxGlobalLongSize(address _token, uint256 _amount)
        external
        onlyOwner
    {
        maxGlobalLongSizes[_token] = _amount;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
    mapping(bytes32 => address) public latestExecutedCollateral;
    mapping(bytes32 => address) public latestIncreasePendingCollateral;
}
