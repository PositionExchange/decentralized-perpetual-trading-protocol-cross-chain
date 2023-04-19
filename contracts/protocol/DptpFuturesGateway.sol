// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../interfaces/CrosschainFunctionCallInterface.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IVaultUtils.sol";
import "../interfaces/IShortsTracker.sol";
import "../token/interface/IWETH.sol";
import {Errors} from "./libraries/helpers/Errors.sol";

contract DptpFuturesGateway is
    PausableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;
    using SafeCastUpgradeable for uint256;
    using AddressUpgradeable for address;

    uint256 constant PRICE_DECIMALS = 10**12;

    struct ManagerData {
        // fee = quoteAssetAmount / tollRatio (means if fee = 0.001% then tollRatio = 100000)
        uint24 takerTollRatio;
        uint24 makerTollRatio;
        uint40 baseBasicPoint;
        uint32 basicPoint;
        uint16 contractPrice;
        uint8 assetRfiPercent;
        // minimum order quantity in wei, input quantity must > minimumOrderQuantity
        uint80 minimumOrderQuantity;
        // minimum quantity = 0.001 then stepBaseSize = 1000
        uint32 stepBaseSize;
    }

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
        OPEN_MARKET_BY_QUOTE
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

    uint256 public pcsId;
    address public pscCrossChainGateway;

    address public futuresAdapter;
    address public vault;
    address public shortsTracker;
    address public weth;

    mapping(address => ManagerData) public positionManagerConfigData;

    mapping(address => bool) public positionKeepers;

    mapping(address => uint256) public increasePositionsIndex;
    mapping(bytes32 => IncreasePositionRequest) public increasePositionRequests;

    mapping(address => uint256) public decreasePositionsIndex;
    mapping(bytes32 => DecreasePositionRequest) public decreasePositionRequests;

    mapping(address => uint256) public maxGlobalLongSizes;
    mapping(address => uint256) public maxGlobalShortSizes;

    bytes32[] public increasePositionRequestKeys;
    bytes32[] public decreasePositionRequestKeys;

    uint256 public maxTimeDelay;
    uint256 public executionFee;

    function initialize(
        uint256 _pcsId,
        address _pscCrossChainGateway,
        address _futuresAdapter,
        address _vault,
        address _weth,
        uint256 _executionFee
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
        __Pausable_init();

        pcsId = _pcsId;

        require(_pscCrossChainGateway != address(0), Errors.VL_EMPTY_ADDRESS);
        pscCrossChainGateway = _pscCrossChainGateway;

        require(_futuresAdapter != address(0), Errors.VL_EMPTY_ADDRESS);
        futuresAdapter = _futuresAdapter;

        require(_vault != address(0), Errors.VL_EMPTY_ADDRESS);
        vault = _vault;

        require(_weth != address(0), Errors.VL_EMPTY_ADDRESS);
        weth = _weth;

        executionFee = _executionFee;
    }

    function createIncreasePositionRequest(
        address[] memory _path,
        address _indexToken,
        uint256 _amountInUsd,
        uint256 _sizeDeltaToken,
        uint16 _leverage,
        bool _isLong
    ) external payable nonReentrant returns (bytes32) {
        require(msg.value == executionFee, "fee");
        require(_path.length == 1 || _path.length == 2, "len");
        // TODO: Consider move this to manager config
        require(_leverage > 1, "min leverage");
        _validateSize(_indexToken, _sizeDeltaToken, false);
        _validateToken(_path[_path.length - 1], _indexToken, _isLong);

        uint256 amountInToken = IVault(vault).usdToTokenMin(
            _path[0],
            _amountInUsd.mul(PRICE_DECIMALS)
        );

        uint256 feeInUsd = _calculateMarginFees(
            msg.sender,
            _path,
            _indexToken,
            _isLong,
            amountInToken,
            _amountInUsd,
            _leverage,
            false
        );

        uint256 amountInAfterFeeToken = IVault(vault).usdToTokenMin(
            _path[0],
            _amountInUsd.add(feeInUsd).mul(PRICE_DECIMALS)
        );

        _transferIn(_path[0], amountInAfterFeeToken);
        _transferInETH();

        CreateIncreasePositionParam memory params = CreateIncreasePositionParam(
            msg.sender,
            _path,
            _indexToken,
            amountInAfterFeeToken,
            _amountInUsd,
            feeInUsd,
            _sizeDeltaToken,
            0,
            _leverage,
            _isLong,
            false
        );
        return _createIncreasePosition(params);
    }

    //    function createIncreasePositionETH(
    //        address[] memory _path,
    //        address _indexToken,
    //        uint256 _amountInUsd,
    //        uint256 _sizeDeltaToken,
    //        uint16 _leverage,
    //        bool _isLong
    //    ) external payable nonReentrant returns (bytes32) {
    //        require(msg.value >= executionFee, "fee");
    //        require(_path.length == 1 || _path.length == 2, "len");
    //        require(_path[0] == weth, "path");
    //        _validateSize(_path[0], _sizeDeltaToken, false);
    //
    //        uint256 amountInToken = msg.value.sub(executionFee);
    //        _transferInETH();
    //
    //        CreateIncreasePositionParam memory params = CreateIncreasePositionParam(
    //            msg.sender,
    //            _path,
    //            _indexToken,
    //            amountInToken,
    //            _amountInUsd,
    //            _sizeDeltaToken,
    //            0,
    //            _leverage,
    //            _isLong,
    //            false
    //        );
    //        return _createIncreasePosition(params);
    //    }

    function createIncreaseOrderRequest(
        address[] memory _path,
        address _indexToken,
        uint256 _amountInUsd,
        uint256 _pip,
        uint256 _sizeDeltaToken,
        uint16 _leverage,
        bool _isLong
    ) external payable nonReentrant returns (bytes32) {
        require(msg.value == executionFee, "fee");
        require(_path.length == 1 || _path.length == 2, "len");
        // TODO: Consider move this to manager config
        require(_leverage > 1, "min leverage");
        _validateSize(_indexToken, _sizeDeltaToken, false);
        _validateToken(_path[_path.length - 1], _indexToken, _isLong);

        uint256 amountInToken = IVault(vault).usdToTokenMin(
            _path[0],
            _amountInUsd.mul(PRICE_DECIMALS)
        );

        uint256 feeInUsd = _calculateMarginFees(
            msg.sender,
            _path,
            _indexToken,
            _isLong,
            amountInToken,
            _amountInUsd,
            _leverage,
            true
        );

        uint256 amountInAfterFeeToken = IVault(vault).usdToTokenMin(
            _path[0],
            _amountInUsd.add(feeInUsd).mul(PRICE_DECIMALS)
        );

        _transferIn(_path[0], amountInAfterFeeToken);
        _transferInETH();

        CreateIncreasePositionParam memory params = CreateIncreasePositionParam(
            msg.sender,
            _path,
            _indexToken,
            amountInAfterFeeToken,
            _amountInUsd,
            feeInUsd,
            _sizeDeltaToken,
            _pip,
            _leverage,
            _isLong,
            false
        );

        return _createIncreasePosition(params);
    }

    function createDecreasePositionRequest(
        address[] memory _path,
        address _indexToken,
        uint256 _sizeDeltaToken,
        bool _isLong,
        bool _withdrawETH
    ) external payable nonReentrant returns (bytes32) {
        require(msg.value == executionFee, "val");
        require(_path.length == 1 || _path.length == 2, "len");
        _validateSize(_indexToken, _sizeDeltaToken, false);
        _validateToken(_path[0], _indexToken, _isLong);

        if (_withdrawETH) {
            require(_path[_path.length - 1] == weth, "path");
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
    ) external payable nonReentrant returns (bytes32) {
        require(msg.value == executionFee, "val");
        require(_path.length == 1 || _path.length == 2, "len");
        _validateSize(_indexToken, _sizeDeltaToken, false);
        _validateToken(_path[0], _indexToken, _isLong);

        if (_withdrawETH) {
            require(_path[_path.length - 1] == weth, "path");
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
        uint256 _entryPip,
        uint256 _sizeDeltaInToken,
        bool _isLong
    ) public nonReentrant {
        //        require(positionKeepers[msg.sender], "403");

        IncreasePositionRequest memory request = increasePositionRequests[_key];
        if (request.account == address(0)) {
            return;
        }

        delete increasePositionRequests[_key];

        if (request.amountInToken > 0) {
            uint256 amountInToken = uint256(request.amountInToken);

            if (request.path.length > 1) {
                IERC20Upgradeable(request.path[0]).safeTransfer(
                    vault,
                    amountInToken
                );
                amountInToken = _swap(request.path, address(this), false);
            }

            IERC20Upgradeable(request.path[request.path.length - 1])
                .safeTransfer(vault, amountInToken);
        }

        uint256 feeUsd = request.feeUsd.mul(PRICE_DECIMALS);
        _increasePosition(
            request.account,
            request.path[request.path.length - 1],
            request.indexToken,
            _entryPip,
            _sizeDeltaInToken,
            _isLong,
            feeUsd
        );
        _transferOutETH(executionFee, payable(msg.sender));

        emit ExecuteIncreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.amountInToken,
            _sizeDeltaInToken,
            _isLong,
            feeUsd
        );
    }

    function executeDecreasePosition(
        bytes32 _key,
        uint256 _amountOutAfterFeesUsd,
        uint256 _feeUsd,
        uint256 _entryPip,
        uint256 _sizeDeltaToken,
        bool _isLong
    ) public nonReentrant {
        //        require(positionKeepers[msg.sender], "403");

        DecreasePositionRequest memory request = decreasePositionRequests[_key];
        if (request.account == address(0)) {
            return;
        }
        delete decreasePositionRequests[_key];

        address collateralToken = request.path[0];
        uint256 amountOutTokenAfterFees;
        uint256 reduceCollateralAmount;
        {
            address account = request.account;
            address indexToken = request.indexToken;
            uint256 entryPip = _entryPip;
            uint256 sizeDeltaToken = _sizeDeltaToken;
            bool isLong = _isLong;
            uint256 amountOutAfterFeesUsd = _amountOutAfterFeesUsd;
            uint256 feeUsd = _feeUsd;
            (
                amountOutTokenAfterFees,
                reduceCollateralAmount
            ) = _decreasePosition(
                account,
                collateralToken,
                indexToken,
                entryPip,
                sizeDeltaToken,
                isLong,
                address(this),
                amountOutAfterFeesUsd.mul(PRICE_DECIMALS),
                feeUsd.mul(PRICE_DECIMALS)
            );
        }

        _transferOutETH(executionFee, payable(msg.sender));

        emit ExecuteDecreasePosition(
            request.account,
            request.path,
            request.indexToken,
            _sizeDeltaToken,
            _isLong,
            executionFee
        );

        if (amountOutTokenAfterFees == 0) {
            if (reduceCollateralAmount == 0) {
                return;
            }
            CrosschainFunctionCallInterface(futuresAdapter).crossBlockchainCall(
                pcsId,
                pscCrossChainGateway,
                uint8(Method.REMOVE_MARGIN),
                abi.encode(
                    collateralToken,
                    request.indexToken,
                    coreManagers[request.indexToken],
                    reduceCollateralAmount,
                    0,
                    msg.sender,
                    false
                )
            );
            return;
        }

        if (request.path.length > 1) {
            IERC20Upgradeable(collateralToken).safeTransfer(
                vault,
                amountOutTokenAfterFees
            );
            amountOutTokenAfterFees = _swap(request.path, address(this), true);
        }

        if (request.withdrawETH) {
            _transferOutETH(amountOutTokenAfterFees, payable(request.account));
            return;
        }

        _transferOut(
            request.path[request.path.length - 1],
            amountOutTokenAfterFees,
            payable(request.account)
        );
    }

    function createCancelOrderRequest(
        bytes32 _key,
        uint256 _orderIdx,
        bool _isReduce
    ) external payable nonReentrant {
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
        require(account == msg.sender, "403");

        CrosschainFunctionCallInterface(futuresAdapter).crossBlockchainCall(
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

    function executeCancelIncreaseOrder(bytes32 _key, bool _isReduce)
        external
        payable
        nonReentrant
    {
        //        require(positionKeepers[msg.sender], "403");
        if (_isReduce) {
            delete decreasePositionRequests[_key];
            return;
        }

        IncreasePositionRequest memory request = increasePositionRequests[_key];
        delete increasePositionRequests[_key];

        _transferOut(
            request.path[0],
            request.amountInToken,
            payable(request.account)
        );
    }

    function liquidatePosition(
        address _trader,
        address _collateralToken,
        address _indexToken,
        uint256 _positionSize,
        bool _isLong
    ) public nonReentrant {
        IVault(vault).liquidatePosition(
            _trader,
            _collateralToken,
            _indexToken,
            _positionSize,
            _isLong
        );
    }

    function createAddCollateralRequest(
        address _collateralToken,
        address _indexToken,
        uint256 _amountInUsd,
        bool _isLong
    ) external nonReentrant {
        IVault(vault).validateTokens(_collateralToken, _indexToken, _isLong);
        uint256 amountInToken = IVault(vault).usdToTokenMin(
            _collateralToken,
            _amountInUsd.mul(PRICE_DECIMALS)
        );
        _transferIn(_collateralToken, amountInToken);
        CrosschainFunctionCallInterface(futuresAdapter).crossBlockchainCall(
            pcsId,
            pscCrossChainGateway,
            uint8(Method.ADD_MARGIN),
            abi.encode(
                _collateralToken,
                _indexToken,
                coreManagers[_indexToken],
                _amountInUsd,
                amountInToken,
                msg.sender
            )
        );
    }

    function createRemoveCollateralRequest(
        address _collateralToken,
        address _indexToken,
        uint256 _amountInUsd,
        bool _isLong
    ) external nonReentrant {
        IVault(vault).validateTokens(_collateralToken, _indexToken, _isLong);
        CrosschainFunctionCallInterface(futuresAdapter).crossBlockchainCall(
            pcsId,
            pscCrossChainGateway,
            uint8(Method.REMOVE_MARGIN),
            abi.encode(
                _collateralToken,
                _indexToken,
                coreManagers[_indexToken],
                _amountInUsd,
                0,
                msg.sender,
                true
            )
        );
    }

    function executeAddCollateral(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _amountInToken
    ) external nonReentrant {
        //        require(positionKeepers[msg.sender], "403");

        IVault(vault).addCollateral(
            _account,
            _collateralToken,
            _indexToken,
            _isLong,
            _amountInToken
        );
        emit CollateralAdded(_account, _collateralToken, _amountInToken);
    }

    function executeRemoveCollateral(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _amountOutUsd
    ) external nonReentrant {
        //        require(positionKeepers[msg.sender], "403");
        if (_amountOutUsd == 0) {
            return;
        }
        uint256 amountOutToken = IVault(vault).usdToTokenMin(
            _collateralToken,
            _amountOutUsd.mul(PRICE_DECIMALS)
        );
        IVault(vault).removeCollateral(
            _account,
            _collateralToken,
            _indexToken,
            _isLong,
            amountOutToken
        );
        _transferOut(_collateralToken, amountOutToken, payable(_account));
        emit CollateralRemove(_account, _collateralToken, amountOutToken);
    }

    function setTPSL(
        address[] memory _path,
        address _indexToken,
        bool _withdrawETH,
        uint128 _higherPip,
        uint128 _lowerPip,
        SetTPSLOption _option
    ) external nonReentrant {
        bytes32 requestKey = _createTPSLDecreaseOrder(
            msg.sender,
            _path,
            _indexToken,
            _withdrawETH
        );
        if (_option == SetTPSLOption.ONLY_HIGHER) {
            TPSLRequestMap[
                _getTPSLRequestKey(msg.sender, _indexToken, true)
            ] = requestKey;
        } else if (_option == SetTPSLOption.ONLY_LOWER) {
            TPSLRequestMap[
                _getTPSLRequestKey(msg.sender, _indexToken, false)
            ] = requestKey;
        } else if (_option == SetTPSLOption.BOTH) {
            TPSLRequestMap[
                _getTPSLRequestKey(msg.sender, _indexToken, true)
            ] = requestKey;
            TPSLRequestMap[
                _getTPSLRequestKey(msg.sender, _indexToken, false)
            ] = requestKey;
        }
        CrosschainFunctionCallInterface(futuresAdapter).crossBlockchainCall(
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

    function unsetTPAndSL(address _indexToken) external nonReentrant {
        delete decreasePositionRequests[
            TPSLRequestMap[_getTPSLRequestKey(msg.sender, _indexToken, true)]
        ];
        delete TPSLRequestMap[
            _getTPSLRequestKey(msg.sender, _indexToken, true)
        ];
        delete decreasePositionRequests[
            TPSLRequestMap[_getTPSLRequestKey(msg.sender, _indexToken, false)]
        ];
        delete TPSLRequestMap[
            _getTPSLRequestKey(msg.sender, _indexToken, false)
        ];
        CrosschainFunctionCallInterface(futuresAdapter).crossBlockchainCall(
            pcsId,
            pscCrossChainGateway,
            uint8(Method.UNSET_TP_AND_SL),
            abi.encode(coreManagers[_indexToken], msg.sender)
        );
    }

    function unsetTPOrSL(address _indexToken, bool _isHigherPrice)
        external
        nonReentrant
    {
        if (_isHigherPrice) {
            delete decreasePositionRequests[
                TPSLRequestMap[
                    _getTPSLRequestKey(msg.sender, _indexToken, true)
                ]
            ];
            delete TPSLRequestMap[
                _getTPSLRequestKey(msg.sender, _indexToken, true)
            ];
        } else {
            delete decreasePositionRequests[
                TPSLRequestMap[
                    _getTPSLRequestKey(msg.sender, _indexToken, false)
                ]
            ];
            delete TPSLRequestMap[
                _getTPSLRequestKey(msg.sender, _indexToken, false)
            ];
        }
        CrosschainFunctionCallInterface(futuresAdapter).crossBlockchainCall(
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
        address indexToken = indexTokens[_positionManager];
        // delete untriggered tp or sl order
        delete decreasePositionRequests[
            TPSLRequestMap[
                _getTPSLRequestKey(_account, indexToken, !_isHigherPrice)
            ]
        ];
        delete TPSLRequestMap[
            _getTPSLRequestKey(_account, indexToken, !_isHigherPrice)
        ];

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
        delete decreasePositionRequests[TPSLRequestMap[triggeredTPSLKey]];
        delete TPSLRequestMap[triggeredTPSLKey];
    }

    function _increasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _entryPip,
        uint256 _sizeDeltaToken,
        bool _isLong,
        uint256 _feeUsd
    ) internal {
        uint32 basisPoint = positionManagerConfigData[_indexToken].basicPoint;
        require(basisPoint > 0, "invalid basis point");
        _entryPip = _entryPip.mul(PRICE_DECIMALS).div(basisPoint);
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
            _entryPip,
            _sizeDeltaToken,
            _isLong,
            _feeUsd
        );
    }

    function _decreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _entryPip,
        uint256 _sizeDeltaToken,
        bool _isLong,
        address _receiver,
        uint256 _amountOutUsd,
        uint256 _feeUsd
    ) internal returns (uint256, uint256) {
        uint32 basisPoint = positionManagerConfigData[_indexToken].basicPoint;
        require(basisPoint > 0, "invalid basis point");
        _entryPip = _entryPip.mul(PRICE_DECIMALS).div(basisPoint);
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
                _entryPip,
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
                CrosschainFunctionCallInterface(futuresAdapter)
                    .crossBlockchainCall(
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
                            amountUsd
                        )
                    );
            } else {
                CrosschainFunctionCallInterface(futuresAdapter)
                    .crossBlockchainCall(
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
                            amountUsd
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
            CrosschainFunctionCallInterface(futuresAdapter).crossBlockchainCall(
                pcsId,
                pscCrossChainGateway,
                uint8(Method.CLOSE_POSITION),
                abi.encode(
                    requestKey,
                    coreManagers[request.path[0]],
                    _sizeDeltaToken,
                    msg.sender
                )
            );
        } else {
            CrosschainFunctionCallInterface(futuresAdapter).crossBlockchainCall(
                pcsId,
                pscCrossChainGateway,
                uint8(Method.CLOSE_LIMIT_POSITION),
                abi.encode(
                    requestKey,
                    coreManagers[request.path[0]],
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

    function _transferIn(address _token, uint256 _tokenAmount) internal {
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
        address payable _account
    ) internal {
        IERC20Upgradeable(_token).safeTransfer(_account, _tokenAmount);
    }

    function _transferOutETH(uint256 _amountOut, address payable _account)
        internal
    {
        if (msg.value != 0) {
            IWETH(weth).transfer(_account, _amountOut);
        }
    }

    function _calculateMarginFees(
        address _trader,
        address[] memory _path,
        address _indexToken,
        bool _isLong,
        uint256 _amountInToken,
        uint256 _amountInUsd,
        uint256 _leverage,
        bool _isLimitOrder
    ) internal returns (uint256) {
        // Fee for opening and closing position
        uint256 positionFee = _getPositionFee(
            _indexToken,
            _amountInUsd,
            _leverage,
            _isLimitOrder
        );
        uint256 borrowingFee = IVault(vault).getBorrowingFee(
            _trader,
            _path[_path.length - 1],
            _indexToken,
            _isLong
        );
        borrowingFee = borrowingFee.div(PRICE_DECIMALS);
        uint256 swapFee = _path.length > 1
            ? IVault(vault).getSwapFee(_path[0], _path[1], _amountInToken)
            : 0;

        emit CollectFees(_amountInToken, positionFee, borrowingFee, swapFee);

        return positionFee.add(borrowingFee).add(swapFee);
    }

    function _getPositionFee(
        address _indexToken,
        uint256 _amountInUsd,
        uint256 _leverage,
        bool _isLimitOrder
    ) internal view returns (uint256 fee) {
        uint256 tollRatio;
        if (_isLimitOrder) {
            tollRatio = uint256(
                positionManagerConfigData[_indexToken].makerTollRatio
            );
        } else {
            tollRatio = uint256(
                positionManagerConfigData[_indexToken].takerTollRatio
            );
        }
        if (tollRatio != 0) {
            fee = (_amountInUsd * _leverage) / tollRatio;
        }
        return fee;
    }

    function getRequestKey(address _account, uint256 _index)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_account, _index));
    }

    function _getTPSLRequestKey(
        address _account,
        address _indexToken,
        bool _isHigherPip
    ) internal returns (bytes32) {
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

    function _validateToken(
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) internal view {
        bool _isTokenValid = IVault(vault).validateTokens(
            _collateralToken,
            _indexToken,
            _isLong
        );
        require(_isTokenValid, "token invalid");
    }

    function _validateSize(
        address _manager,
        uint256 _size,
        bool _isCloseOrder
    ) internal view {
        ManagerData memory managerConfigData = positionManagerConfigData[
            _manager
        ];

        // not validate minimumOrderQuantity if it's a close order
        if (!_isCloseOrder) {
            require(
                _size >= managerConfigData.minimumOrderQuantity,
                Errors.VL_INVALID_QUANTITY
            );
        }
        if (managerConfigData.stepBaseSize != 0) {
            uint256 remainder = _size %
                (10**18 / managerConfigData.stepBaseSize);
            require(remainder == 0, Errors.VL_INVALID_QUANTITY);
        }
    }

    function _validateMaxGlobalSize(
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta
    ) internal view {
        if (_sizeDelta == 0) {
            return;
        }

        if (_isLong) {
            uint256 maxGlobalLongSize = maxGlobalLongSizes[_indexToken];
            if (
                maxGlobalLongSize > 0 &&
                IVault(vault).guaranteedUsd(_indexToken).add(_sizeDelta) >
                maxGlobalLongSize
            ) {
                revert("max longs exceeded");
            }
        } else {
            uint256 maxGlobalShortSize = maxGlobalShortSizes[_indexToken];
            if (
                maxGlobalShortSize > 0 &&
                IVault(vault).globalShortSizes(_indexToken).add(_sizeDelta) >
                maxGlobalShortSize
            ) {
                revert("max shorts exceeded");
            }
        }
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

    function setPositionManagerConfigData(
        address _positionManager,
        uint24 _takerTollRatio,
        uint24 _makerTollRatio,
        uint32 _basicPoint,
        uint40 _baseBasicPoint,
        uint16 _contractPrice,
        uint8 _assetRfiPercent,
        uint80 _minimumOrderQuantity,
        uint32 _stepBaseSize
    ) public onlyOwner {
        require(_positionManager != address(0), Errors.VL_EMPTY_ADDRESS);
        positionManagerConfigData[_positionManager]
            .takerTollRatio = _takerTollRatio;
        positionManagerConfigData[_positionManager]
            .makerTollRatio = _makerTollRatio;
        positionManagerConfigData[_positionManager].basicPoint = _basicPoint;
        positionManagerConfigData[_positionManager]
            .baseBasicPoint = _baseBasicPoint;
        positionManagerConfigData[_positionManager]
            .contractPrice = _contractPrice;
        positionManagerConfigData[_positionManager]
            .assetRfiPercent = _assetRfiPercent;
        positionManagerConfigData[_positionManager]
            .minimumOrderQuantity = _minimumOrderQuantity;
        positionManagerConfigData[_positionManager]
            .stepBaseSize = _stepBaseSize;
    }

    function setManagerTakerTollRatio(
        address _positionManager,
        uint24 _takerTollRatio
    ) public onlyOwner {
        require(_positionManager != address(0), Errors.VL_EMPTY_ADDRESS);
        positionManagerConfigData[_positionManager]
            .takerTollRatio = _takerTollRatio;
    }

    function setManagerMakerTollRatio(
        address _positionManager,
        uint24 _makerTollRatio
    ) public onlyOwner {
        require(_positionManager != address(0), Errors.VL_EMPTY_ADDRESS);
        positionManagerConfigData[_positionManager]
            .makerTollRatio = _makerTollRatio;
    }

    function setManagerBaseBasicPoint(
        address _positionManager,
        uint40 _baseBasicPoint
    ) public onlyOwner {
        require(_positionManager != address(0), Errors.VL_EMPTY_ADDRESS);
        positionManagerConfigData[_positionManager]
            .baseBasicPoint = _baseBasicPoint;
    }

    function setManagerBasicPoint(address _positionManager, uint32 _basicPoint)
        public
        onlyOwner
    {
        require(_positionManager != address(0), Errors.VL_EMPTY_ADDRESS);
        positionManagerConfigData[_positionManager].basicPoint = _basicPoint;
    }

    function setManagerContractPrice(
        address _positionManager,
        uint16 _contractPrice
    ) public onlyOwner {
        require(_positionManager != address(0), Errors.VL_EMPTY_ADDRESS);
        positionManagerConfigData[_positionManager]
            .contractPrice = _contractPrice;
    }

    function setManagerAssetRFI(
        address _positionManager,
        uint8 _assetRfiPercent
    ) public onlyOwner {
        require(_positionManager != address(0), Errors.VL_EMPTY_ADDRESS);
        positionManagerConfigData[_positionManager]
            .assetRfiPercent = _assetRfiPercent;
    }

    function setMinimumOrderQuantity(
        address _positionManager,
        uint80 _minimumOrderQuantity
    ) public onlyOwner {
        require(_positionManager != address(0), Errors.VL_EMPTY_ADDRESS);
        positionManagerConfigData[_positionManager]
            .minimumOrderQuantity = _minimumOrderQuantity;
    }

    function setStepBaseSize(address _positionManager, uint32 _stepBaseSize)
        public
        onlyOwner
    {
        require(_positionManager != address(0), Errors.VL_EMPTY_ADDRESS);
        positionManagerConfigData[_positionManager]
            .stepBaseSize = _stepBaseSize;
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

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
    // mapping indexToken with positionManager
    mapping(address => address) public coreManagers;
    // mapping positionManager with indexToken
    mapping(address => address) public indexTokens;
    mapping(bytes32 => bytes32) public TPSLRequestMap;
}
