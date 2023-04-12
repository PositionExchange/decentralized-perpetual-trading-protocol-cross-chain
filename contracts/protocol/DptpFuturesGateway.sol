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
        uint256 amountInToken;
        uint256 amountInUsd;
        uint256 sizeDeltaToken;
        uint256 pip;
        uint16 leverage;
        bool isLong;
        bool hasCollateralInETH;
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
        uint256 sizeDelta,
        bool isLong,
        uint256 executionFee,
        bytes32 key,
        uint256 blockNumber,
        uint256 blockTime
    );

    event CreateDecreaseOrder(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 pip,
        uint256 sizeDelta,
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
        uint256 executionFee
    );

    event ExecuteDecreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        uint256 executionFee
    );

    event CollectFees(uint256 positionFee, uint256 borrowFee, uint256 totalFee);

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

    function createIncreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _amountInUsd,
        uint256 _sizeDeltaToken,
        uint16 _leverage,
        bool _isLong
    ) external payable nonReentrant returns (bytes32) {
        require(msg.value == executionFee, "fee");
        require(_path.length == 1 || _path.length == 2, "len");
        _validateSize(_path[0], _sizeDeltaToken, false);

        uint256 amountInToken = IVault(vault).usdToTokenMin(
            _path[0],
            _amountInUsd.mul(PRICE_DECIMALS)
        );
        _transferIn(_path[0], amountInToken);
        _transferInETH();

        CreateIncreasePositionParam memory params = CreateIncreasePositionParam(
            msg.sender,
            _path,
            _indexToken,
            amountInToken,
            _amountInUsd,
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

    function createIncreaseOrder(
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
        _validateSize(_path[0], _sizeDeltaToken, false);

        ManagerData memory managerConfigData = positionManagerConfigData[
            _path[0]
        ];

        uint256 amountInToken = IVault(vault).usdToTokenMin(
            _path[0],
            _amountInUsd.mul(PRICE_DECIMALS)
        );

        _transferIn(_path[0], amountInToken);
        _transferInETH();

        CreateIncreasePositionParam memory params = CreateIncreasePositionParam(
            msg.sender,
            _path,
            _indexToken,
            amountInToken,
            _amountInUsd,
            _sizeDeltaToken,
            _pip,
            _leverage,
            _isLong,
            false
        );

        return _createIncreasePosition(params);
    }

    function createDecreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _sizeDeltaToken,
        bool _isLong,
        bool _withdrawETH
    ) external payable nonReentrant returns (bytes32) {
        require(msg.value == executionFee, "val");
        require(_path.length == 1 || _path.length == 2, "len");
        _validateSize(_path[0], _sizeDeltaToken, false);

        if (_withdrawETH) {
            require(_path[_path.length - 1] == weth, "path");
        }

        _transferInETH();

        return
            _createDecreasePosition(
                msg.sender,
                _path,
                _indexToken,
                _sizeDeltaToken,
                _isLong,
                _withdrawETH
            );
    }

    function createDecreaseOrder(
        address[] memory _path,
        address _indexToken,
        uint256 _pip,
        uint256 _sizeDeltaToken,
        bool _isLong,
        bool _withdrawETH
    ) external payable nonReentrant returns (bytes32) {
        require(msg.value == executionFee, "val");
        require(_path.length == 1 || _path.length == 2, "len");
        _validateSize(_path[0], _sizeDeltaToken, false);

        if (_withdrawETH) {
            require(_path[_path.length - 1] == weth, "path");
        }

        _transferInETH();

        return
            _createDecreaseOrder(
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
        uint256 _sizeInToken,
        bool _isLong
    ) public nonReentrant {
        //        require(positionKeepers[msg.sender], "403");

        IncreasePositionRequest memory request = increasePositionRequests[_key];
        if (request.account == address(0)) {
            return;
        }
        uint256 sizeDelta = IVault(vault).tokenToUsdMinWithAdjustment(
            request.path[0],
            _sizeInToken
        );
        _validateMaxGlobalSize(request.indexToken, _isLong, sizeDelta);

        delete increasePositionRequests[_key];

        if (request.amountInToken > 0) {
            uint256 amountInToken = uint256(request.amountInToken);

            if (request.path.length > 1) {
                IERC20Upgradeable(request.path[0]).safeTransfer(
                    vault,
                    amountInToken
                );
                amountInToken = _swap(request.path, address(this));
            }

            IERC20Upgradeable(request.path[request.path.length - 1])
                .safeTransfer(vault, amountInToken);
        }

        _increasePosition(
            request.account,
            request.path[request.path.length - 1],
            request.indexToken,
            sizeDelta,
            _isLong,
            uint256(request.feeUsd)
        );
        _transferOutETH(executionFee, payable(msg.sender));

        emit ExecuteIncreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.amountInToken,
            sizeDelta,
            _isLong,
            executionFee
        );
    }

    function executeDecreasePosition(
        bytes32 _key,
        uint256 _amountOutUsdAfterFees,
        uint256 _feeUsd,
        uint256 _sizeDeltaInToken,
        bool _isLong
    ) public nonReentrant {
        //        require(positionKeepers[msg.sender], "403");

        DecreasePositionRequest memory request = decreasePositionRequests[_key];
        // if the request was already executed or cancelled, return true so that the
        // executeDecreasePositions loop will continue executing the next request
        if (request.account == address(0)) {
            return;
        }

        delete decreasePositionRequests[_key];

        uint256 sizeDelta = IVault(vault).tokenToUsdMinWithAdjustment(
            request.path[0],
            _sizeDeltaInToken
        );
        uint256 amountOutTokenAfterFees = _decreasePosition(
            request.account,
            request.path[0],
            request.indexToken,
            sizeDelta,
            _isLong,
            address(this),
            _amountOutUsdAfterFees.mul(PRICE_DECIMALS),
            _feeUsd.mul(PRICE_DECIMALS)
        );

        if (amountOutTokenAfterFees > 0) {
            if (request.path.length > 1) {
                IERC20Upgradeable(request.path[0]).safeTransfer(
                    vault,
                    amountOutTokenAfterFees
                );
                amountOutTokenAfterFees = _swap(request.path, address(this));
            }

            if (request.withdrawETH) {
                _transferOutETH(
                    amountOutTokenAfterFees,
                    payable(request.account)
                );
            } else {
                _transferOut(
                    request.path[request.path.length - 1],
                    amountOutTokenAfterFees,
                    payable(request.account)
                );
            }
        }

        _transferOutETH(executionFee, payable(msg.sender));

        emit ExecuteDecreasePosition(
            request.account,
            request.path,
            request.indexToken,
            _sizeDeltaInToken,
            _isLong,
            executionFee
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

        _transferOut(request.path[0], request.amountInToken, payable(request.account));

        delete increasePositionRequests[_key];
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

    function createUpdateCollateralRequest(
        address[] memory _path,
        address _indexToken,
        uint256 _amountInUsd,
        bool _isRemove
    ) external nonReentrant {
        uint8 methodId = _isRemove
            ? uint8(Method.REMOVE_MARGIN)
            : uint8(Method.ADD_MARGIN);
        uint256 amountInToken = IVault(vault).usdToTokenMin(
            _path[0],
            _amountInUsd.mul(PRICE_DECIMALS)
        );
        _transferIn(_path[0], _amountInUsd);
        CrosschainFunctionCallInterface(futuresAdapter).crossBlockchainCall(
            pcsId,
            pscCrossChainGateway,
            methodId,
            abi.encode(
                _path[0],
                _indexToken,
                coreManagers[_indexToken],
                _amountInUsd,
                amountInToken,
                msg.sender
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
        uint256 _amountInToken,
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

    function _increasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _feeUsd
    ) internal {
        if (!_isLong && _sizeDelta > 0) {
            uint256 markPrice = _isLong
                ? IVault(vault).getMaxPrice(_indexToken)
                : IVault(vault).getMinPrice(_indexToken);
            // should be called strictly before position is updated in Vault
            IShortsTracker(shortsTracker).updateGlobalShortData(
                _indexToken,
                _sizeDelta,
                markPrice,
                true
            );
        }

        IVault(vault).increasePosition(
            _account,
            _collateralToken,
            _indexToken,
            _sizeDelta,
            _isLong,
            _feeUsd
        );
    }

    function _decreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _amountOutUsd,
        uint256 _feeUsd
    ) internal returns (uint256) {
        if (!_isLong && _sizeDelta > 0) {
            uint256 markPrice = _isLong
                ? IVault(vault).getMinPrice(_indexToken)
                : IVault(vault).getMaxPrice(_indexToken);

            // should be called strictly before position is updated in Vault
            IShortsTracker(shortsTracker).updateGlobalShortData(
                _indexToken,
                _sizeDelta,
                markPrice,
                false
            );
        }

        return
            IVault(vault).decreasePosition(
                _account,
                _collateralToken,
                _indexToken,
                _sizeDelta,
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
        uint256 feeInUsd = _calculateMarginFees(
            msg.sender,
            param.path[0],
            param.indexToken,
            param.isLong,
            param.amountInUsd,
            param.leverage,
            false
        );

        IncreasePositionRequest memory request = IncreasePositionRequest(
            param.account,
            param.path,
            param.indexToken,
            param.hasCollateralInETH,
            param.amountInToken,
            feeInUsd
        );

        (, bytes32 requestKey) = _storeIncreasePositionRequest(request);

        {
            uint256 sizeDelta = param.sizeDeltaToken;
            uint256 pip = param.pip;
            uint16 leverage = param.leverage;
            bool isLong = param.isLong;
            uint256 amountAfterFeeInUsd = param.amountInUsd.sub(feeInUsd);
            if (param.pip > 0) {
                CrosschainFunctionCallInterface(futuresAdapter)
                    .crossBlockchainCall(
                        pcsId,
                        pscCrossChainGateway,
                        uint8(Method.OPEN_LIMIT),
                        abi.encode(
                            requestKey,
                            coreManagers[request.path[0]],
                            isLong,
                            sizeDelta,
                            pip,
                            leverage,
                            msg.sender,
                            amountAfterFeeInUsd
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
                            coreManagers[request.path[0]],
                            isLong,
                            sizeDelta,
                            leverage,
                            msg.sender,
                            amountAfterFeeInUsd
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
            executionFee,
            requestKey
        );

        return requestKey;
    }

    function _createDecreasePosition(
        address _account,
        address[] memory _path,
        address _indexToken,
        uint256 _sizeDelta,
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

        CrosschainFunctionCallInterface(futuresAdapter).crossBlockchainCall(
            pcsId,
            pscCrossChainGateway,
            uint8(Method.CLOSE_POSITION),
            abi.encode(
                requestKey,
                coreManagers[request.path[0]],
                _sizeDelta,
                msg.sender
            )
        );

        emit CreateDecreasePosition(
            request.account,
            request.path,
            request.indexToken,
            _sizeDelta,
            _isLong,
            executionFee,
            requestKey,
            block.number,
            block.timestamp
        );
        return requestKey;
    }

    function _createDecreaseOrder(
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

        emit CreateDecreaseOrder(
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
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _amountInUsd,
        uint256 _leverage,
        bool _isLimitOrder
    ) internal returns (uint256) {
        // Fee for opening and closing position
        uint256 positionFee = _getPositionFee(
            _collateralToken,
            _amountInUsd,
            _leverage,
            _isLimitOrder
        );
        uint256 borrowingFee = IVault(vault).getBorrowingFee(
            _trader,
            _collateralToken,
            _indexToken,
            _isLong
        );
        uint256 feeUsd = positionFee.add(borrowingFee);

        emit CollectFees(positionFee, borrowingFee, feeUsd);

        return feeUsd;
    }

    function _getPositionFee(
        address _collateralToken,
        uint256 _amountInUsd,
        uint256 _leverage,
        bool _isLimitOrder
    ) internal view returns (uint256 fee) {
        uint256 tollRatio;
        if (_isLimitOrder) {
            tollRatio = uint256(
                positionManagerConfigData[_collateralToken].makerTollRatio
            );
        } else {
            tollRatio = uint256(
                positionManagerConfigData[_collateralToken].takerTollRatio
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

    function _swap(address[] memory _path, address _receiver)
        internal
        returns (uint256)
    {
        require(_path.length == 2, "invalid _path.length");
        return IVault(vault).swap(_path[0], _path[1], _receiver);
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
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
    mapping(address => address) public coreManagers;
}
