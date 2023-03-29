// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/CrosschainFunctionCallInterface.sol";
import "../interfaces/IInsuranceFund.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IShortsTracker.sol";
import "..//token/interface/IWETH.sol";
import {Errors} from "./libraries/helpers/Errors.sol";

contract DptpFuturesGateway is
    PausableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

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
        uint256 amountInToken;
        uint256 amountInUsd;
        uint256 feeUsd;
        uint256 sizeDelta;
        bool isLong;
        uint256 executionFee;
        uint256 blockNumber;
        uint256 blockTime;
        bool hasCollateralInETH;
    }

    struct CreateIncreasePositionParam {
        address account;
        address[] path;
        address indexToken;
        uint256 amountInToken;
        uint256 amountInUsd;
        uint256 feeInUsd;
        uint256 sizeDelta;
        uint256 leverage;
        bool isLong;
        uint256 executionFee;
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
        uint256 executionFee,
        uint256 blockGap,
        uint256 timeGap
    );

    uint256 public pcsId;
    address public pscCrossChainGateway;

    address public futuresAdapter;
    address public vault;
    address public shortsTracker;
    address public weth;

    uint256 public minExecutionFee;

    mapping(address => ManagerData) public positionManagerConfigData;

    mapping(address => bool) public isPositionKeeper;

    mapping(address => uint256) public increasePositionsIndex;
    mapping(bytes32 => IncreasePositionRequest) public increasePositionRequests;

    mapping(address => uint256) public maxGlobalLongSizes;
    mapping(address => uint256) public maxGlobalShortSizes;

    bytes32[] public increasePositionRequestKeys;

    uint256 public maxTimeDelay;

    function initialize(
        uint256 _pcsId,
        address _pscCrossChainGateway,
        address _futuresAdapter,
        address _vault,
        address _weth,
        uint256 _minExecutionFee
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

        minExecutionFee = _minExecutionFee;
    }

    function createIncreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _leverage,
        bool _isLong,
        uint256 _executionFee
    ) external payable nonReentrant returns (bytes32) {
        require(_executionFee >= minExecutionFee, "fee");
        require(msg.value == _executionFee, "val");
        require(_path.length == 1 || _path.length == 2, "len");

        uint256 amountInUsd = IVault(vault).tokenToUsdMin(_path[0], _amountIn);
        uint256 feeInUsd = _calculateMarginFees(
            _path[0],
            _indexToken,
            _isLong,
            _amountIn,
            _leverage
        );
        uint256 amountAfterFeeInUsd = amountInUsd.sub(feeInUsd);
        uint256 sizeDelta = amountAfterFeeInUsd.mul(_leverage);
        _validateSize(_path[0], sizeDelta, false);

        _transferInETH();

        if (_amountIn > 0) {
            IERC20(_path[0]).safeTransferFrom(
                msg.sender,
                address(this),
                _amountIn
            );
        }

        CreateIncreasePositionParam memory params = CreateIncreasePositionParam(
            msg.sender,
            _path,
            _indexToken,
            _amountIn,
            amountInUsd,
            feeInUsd,
            sizeDelta,
            _leverage,
            _isLong,
            _executionFee,
            false
        );

        return _createIncreasePosition(params);
    }

    function createIncreasePositionETH(
        address[] memory _path,
        address _indexToken,
        uint256 _leverage,
        bool _isLong,
        uint256 _executionFee
    ) external payable nonReentrant returns (bytes32) {
        require(_executionFee >= minExecutionFee, "fee");
        require(msg.value >= _executionFee, "val");
        require(_path.length == 1 || _path.length == 2, "len");
        require(_path[0] == weth, "path");

        _transferInETH();

        uint256 amountInToken = msg.value.sub(_executionFee);
        uint256 amountInUsd = IVault(vault).tokenToUsdMin(
            _path[0],
            amountInToken
        );
        uint256 feeInUsd = _calculateMarginFees(
            _path[0],
            _indexToken,
            _isLong,
            amountInToken,
            _leverage
        );
        uint256 amountAfterFeeInUsd = amountInUsd.sub(feeInUsd);
        uint256 sizeDelta = amountAfterFeeInUsd.mul(_leverage);
        _validateSize(_path[0], sizeDelta, false);

        CreateIncreasePositionParam memory params = CreateIncreasePositionParam(
            msg.sender,
            _path,
            _indexToken,
            amountInToken,
            amountInUsd,
            feeInUsd,
            sizeDelta,
            _leverage,
            _isLong,
            _executionFee,
            false
        );

        return _createIncreasePosition(params);
    }

    function executeIncreasePosition(bytes32 _key) public nonReentrant {
        IncreasePositionRequest memory request = increasePositionRequests[_key];

        if (request.account == address(0)) {
            return;
        }

        _validateExecutionOrCancellation(request.blockNumber);
        _validateMaxGlobalSize(
            request.indexToken,
            request.isLong,
            request.sizeDelta
        );

        delete increasePositionRequests[_key];

        if (request.amountInToken > 0) {
            uint256 amountInToken = request.amountInToken;

            if (request.path.length > 1) {
                IERC20(request.path[0]).safeTransfer(
                    vault,
                    request.amountInToken
                );
                amountInToken = _swap(request.path, address(this));
            }

            IERC20(request.path[request.path.length - 1]).safeTransfer(
                vault,
                amountInToken
            );
        }

        _increasePosition(
            request.account,
            request.path[request.path.length - 1],
            request.indexToken,
            request.sizeDelta,
            request.isLong,
            request.feeUsd
        );
        _transferOutETH(request.executionFee, payable(msg.sender));

        emit ExecuteIncreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.amountInToken,
            request.sizeDelta,
            request.isLong,
            request.executionFee,
            block.number.sub(request.blockNumber),
            block.timestamp.sub(request.blockTime)
        );
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

    function _createIncreasePosition(CreateIncreasePositionParam memory param)
        internal
        returns (bytes32)
    {
        IncreasePositionRequest memory request = IncreasePositionRequest(
            param.account,
            param.path,
            param.indexToken,
            param.amountInToken,
            param.amountInUsd,
            param.feeInUsd,
            param.sizeDelta,
            param.isLong,
            param.executionFee,
            block.number,
            block.timestamp,
            param.hasCollateralInETH
        );

        (, bytes32 requestKey) = _storeIncreasePositionRequest(request);

        CrosschainFunctionCallInterface(futuresAdapter).crossBlockchainCall(
            pcsId,
            pscCrossChainGateway,
            uint8(Method.OPEN_MARKET),
            abi.encode(
                requestKey,
                request.path[0],
                request.isLong,
                request.sizeDelta,
                param.leverage,
                msg.sender,
                request.amountInUsd.sub(param.feeInUsd)
            )
        );

        emit CreateIncreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.amountInToken,
            request.sizeDelta,
            request.isLong,
            request.executionFee,
            requestKey,
            request.blockNumber,
            request.blockTime
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

    function _transferInETH() internal {
        if (msg.value != 0) {
            IWETH(weth).deposit{value: msg.value}();
        }
    }

    function _transferOutETH(uint256 _amountOut, address payable _account)
        internal
    {
        if (msg.value != 0) {
            IWETH(weth).transfer(_account, _amountOut);
        }
    }

    function _calculateMarginFees(
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _amountIn,
        uint256 _leverage
    ) internal returns (uint256) {
        // Fee for opening and closing position
        uint256 feeUsd = _getPositionFee(
            _collateralToken,
            _amountIn,
            _leverage,
            _isLong
        );

        // TODO: Implement in ticket DPTP-378
        // uint256 fundingFee =
        // getFundingFee(_account, _collateralToken, _indexToken, _isLong, _size, _entryFundingRate);
        // feeUsd = feeUsd.add(fundingFee);

        return feeUsd;
    }

    function _getPositionFee(
        address _collateralToken,
        uint256 _amountIn,
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
            uint256 amountInUSD = IVault(vault).tokenToUsdMin(
                _collateralToken,
                _amountIn
            );
            fee = (amountInUSD * _leverage) / tollRatio;
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

    function receiveFromOtherBlockchain(
        address _manager,
        address _trader,
        uint256 _totalAmount,
        uint256 _busdBonusAmount
    ) external {
        require(msg.sender == futuresAdapter, "only futures adapter");
        //        insuranceFund.withdraw(
        //            _manager,
        //            _trader,
        //            _totalAmount,
        //            _busdBonusAmount
        //        );
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

    function _validateExecutionOrCancellation(uint256 _positionBlockNumber)
        internal
        view
    {
        require(isPositionKeeper[msg.sender], "403");
        require(_positionBlockNumber <= block.number, "time");
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

    function setMinExecutionFee(uint256 _minExecutionFee) external onlyOwner {
        minExecutionFee = _minExecutionFee;
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

    function updateManagerTakerTollRatio(
        address _positionManager,
        uint24 _takerTollRatio
    ) public onlyOwner {
        require(_positionManager != address(0), Errors.VL_EMPTY_ADDRESS);
        positionManagerConfigData[_positionManager]
            .takerTollRatio = _takerTollRatio;
    }

    function updateManagerMakerTollRatio(
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

    function updatePosiChainId(uint256 _posiChainId) external onlyOwner {
        pcsId = _posiChainId;
    }

    function updatePosiChainCrosschainGatewayContract(address _address)
        external
        onlyOwner
    {
        pscCrossChainGateway = _address;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}
