// SPDX-License-Identifier: BUSL-1.1
// pragma solidity ^0.8.8;
//
// import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
// import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
// import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
// import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
// import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
// import "@openzeppelin/contracts/utils/math/SafeMath.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "../interfaces/CrosschainFunctionCallInterface.sol";
// import "../interfaces/IInsuranceFund.sol";
// import {Errors} from "./libraries/helpers/Errors.sol";
//
// contract FuturesGateway is PausableUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
//     using SafeERC20 for IERC20;
//     using SafeMath for uint256;
//
//     struct ManagerData {
//         // fee = quoteAssetAmount / tollRatio (means if fee = 0.001% then tollRatio = 100000)
//         uint24 takerTollRatio;
//         uint24 makerTollRatio;
//         uint40 baseBasicPoint;
//         uint32 basicPoint;
//         uint16 contractPrice;
//         uint8 assetRfiPercent;
//         // minimum order quantity in wei, input quantity must > minimumOrderQuantity
//         uint80 minimumOrderQuantity;
//         // minimum quantity = 0.001 then stepBaseSize = 1000
//         uint32 stepBaseSize;
//     }
//
//     struct IncreasePositionRequest {
//         address account;
//         address[] path;
//         address indexToken;
//         uint256 amountIn;
//         uint256 feeUsd;
//         uint256 sizeDelta;
//         bool isLong;
//         uint256 executionFee;
//         uint256 blockNumber;
//         uint256 blockTime;
//         bool hasCollateralInETH;
//     }
//
//     enum Method {
//         OPEN_MARKET,
//         OPEN_LIMIT,
//         CANCEL_LIMIT,
//         ADD_MARGIN,
//         REMOVE_MARGIN,
//         CLOSE_POSITION,
//         INSTANTLY_CLOSE_POSITION,
//         CLOSE_LIMIT_POSITION,
//         CLAIM_FUND,
//         SET_TPSL,
//         UNSET_TP_AND_SL,
//         UNSET_TP_OR_SL,
//         OPEN_MARKET_BY_QUOTE
//     }
//
//     uint256 public posiChainId;
//     address public posiChainCrosschainGatewayContract;
//
//     CrosschainFunctionCallInterface public futuresAdapter;
//     IInsuranceFund public insuranceFund;
//
//     uint256 public minExecutionFee;
//
//     mapping(address => ManagerData) public positionManagerConfigData;
//
//     mapping(address => bool) public isPositionKeeper;
//
//     mapping(address => uint256) public increasePositionsIndex;
//     mapping(bytes32 => IncreasePositionRequest) public increasePositionRequests;
//
//     mapping(address => uint256) public override maxGlobalLongSizes;
//     mapping(address => uint256) public override maxGlobalShortSizes;
//
//     bytes32[] public increasePositionRequestKeys;
//
//     uint256 public maxTimeDelay;
//
//
//     function initialize(
//         address _futuresAdapter,
//         address _posiChainCrosschainGatewayContract,
//         uint256 _posiChainId,
//         address _insuranceFund
//     ) public initializer {
//         __ReentrancyGuard_init();
//         __Ownable_init();
//         __Pausable_init();
//
//         require(
//             _posiChainCrosschainGatewayContract != address(0),
//             Errors.VL_EMPTY_ADDRESS
//         );
//         require(_futuresAdapter != address(0), Errors.VL_EMPTY_ADDRESS);
//         require(_insuranceFund != address(0), Errors.VL_EMPTY_ADDRESS);
//         futuresAdapter = CrosschainFunctionCallInterface(_futuresAdapter);
//         posiChainCrosschainGatewayContract = _posiChainCrosschainGatewayContract;
//         posiChainId = _posiChainId;
//         insuranceFund = IInsuranceFund(_insuranceFund);
//     }
//
//     function createIncreasePosition(
//         address[] memory _path,
//         address _indexToken,
//         uint256 _amountIn,
//         uint256 _sizeDelta,
//         bool _isLong,
//         uint256 _executionFee
//     ) external payable nonReentrant returns (bytes32) {
//         require(_executionFee >= minExecutionFee, "fee");
//         require(msg.value == _executionFee, "val");
//         require(_path.length == 1 || _path.length == 2, "len");
//         _validateQuantity(_positionManager, _quantity, false);
//
//         _transferInETH();
//
//         if (_amountIn > 0) {
//             IERC20(_path[0]).safeTransferFrom(msg.sender, address(this), _amountIn);
//         }
//
//         return _createIncreasePosition(
//             msg.sender,
//             _path,
//             _indexToken,
//             _amountIn,
//             _sizeDelta,
//             _isLong,
//             _executionFee,
//             false
//         );
//     }
//
//     function createIncreasePositionETH(
//         address[] memory _path,
//         address _indexToken,
//         uint256 _sizeDelta,
//         bool _isLong,
//         uint256 _executionFee
//     ) external payable nonReentrant returns (bytes32) {
//         require(_executionFee >= minExecutionFee, "fee");
//         require(msg.value >= _executionFee, "val");
//         require(_path.length == 1 || _path.length == 2, "len");
//         //        require(_path[0] == weth, "path");
//         _validateQuantity(_positionManager, _quantity, false);
//
//         _transferInETH();
//
//         uint256 amountIn = msg.value.sub(_executionFee);
//
//         return _createIncreasePosition(
//             msg.sender,
//             _path,
//             _indexToken,
//             amountIn,
//             _sizeDelta,
//             _isLong,
//             _executionFee,
//             true
//         );
//     }
//
//     function executeIncreasePosition(bytes32 _key, address payable _executionFeeReceiver) public nonReentrant {
//         IncreasePositionRequest memory request = increasePositionRequests[_key];
//
//         if (request.account == address(0)) {
//             return;
//         }
//
//         _validateExecutionOrCancellation(request.blockNumber);
//         _validateMaxGlobalSize(_indexToken, _isLong, _sizeDelta);
//
//         delete increasePositionRequests[_key];
//
//         if (request.amountIn > 0) {
//             uint256 amountIn = request.amountIn;
//
//             if (request.path.length > 1) {
//                 IERC20(request.path[0]).safeTransfer(vault, request.amountIn);
//                 amountIn = _swap(request.path, address(this));
//             }
//
//             IERC20(request.path[request.path.length - 1]).safeTransfer(vault, amountIn);
//         }
//
//         _increasePosition(request.account, request.path[request.path.length - 1], request.indexToken, request.sizeDelta, request.isLong);
//         _transferOutETH(request.executionFee, _executionFeeReceiver);
//
//         return true;
//     }
//
//     function _increasePosition(address _account, address _collateralToken, address _indexToken, uint256 _sizeDelta, bool _isLong) internal {
//         // should be called strictly before position is updated in Vault
//         IShortsTracker(_shortsTracker).updateGlobalShortData(_account, _collateralToken, _indexToken, _isLong, _sizeDelta, markPrice, true);
//
//         IVault(vault).increasePosition(_account, _collateralToken, _indexToken, _sizeDelta, _isLong);
//     }
//
//     function _createIncreasePosition(
//         address _account,
//         address[] memory _path,
//         address _indexToken,
//         uint256 _amountIn,
//         uint256 _sizeDelta,
//         bool _isLong,
//         uint256 _executionFee,
//         bool _hasCollateralInETH
//     ) internal returns (bytes32) {
//
//         // Calculate fee
//         (uint256 feeInUsd, uint256 feeInToken) = _calculateMarginFees(_path[0], _indexToken, _isLong, _sizeDelta);
//
//         IncreasePositionRequest memory request = IncreasePositionRequest(
//             _account,
//             _path,
//             _indexToken,
//             _amountIn,
//             feeInToken,
//             _sizeDelta,
//             _isLong,
//             _executionFee,
//             block.number,
//             block.timestamp,
//             _hasCollateralInETH
//         );
//
//         (uint256 index, bytes32 requestKey) = _storeIncreasePositionRequest(request);
//
//         futuresAdapter.crossBlockchainCall(
//             posiChainId,
//             posiChainCrosschainGatewayContract,
//             uint8(Method.OPEN_MARKET),
//             abi.encode(
//                 requestKey,
//                 _positionManager,
//                 _side,
//                 _quantity,
//                 _leverage,
//                 msg.sender,
//                 _amountIn.sub(feeInUsd)
//             )
//         );
//
//         return requestKey;
//     }
//
//     function _storeIncreasePositionRequest(IncreasePositionRequest memory _request) internal returns (uint256, bytes32) {
//         address account = _request.account;
//         uint256 index = increasePositionsIndex[account].add(1);
//         increasePositionsIndex[account] = index;
//         bytes32 key = getRequestKey(account, index);
//
//         increasePositionRequests[key] = _request;
//         increasePositionRequestKeys.push(key);
//
//         return (index, key);
//     }
//
//     function _transferInETH() internal {
//         //        if (msg.value != 0) {
//         //            IWETH(weth).deposit{value: msg.value}();
//         //        }
//     }
//
//     function _transferOutETH(uint256 _amountOut, address payable _account) internal {
//         //        if (msg.value != 0) {
//         //            IWETH(weth).deposit{value: msg.value}();
//         //        }
//     }
//
//     function _calculateMarginFees(address _collateralToken, address _indexToken, bool _isLong, uint256 _sizeDelta) private returns (uint256, uint256) {
//
//         // Fee for opening and closing position
//         uint256 feeUsd = _getPositionFee(_collateralToken, _size, _leverage, _isLong);
//
//         // TODO: Implement in ticket DPTP-378
//         // uint256 fundingFee = getFundingFee(_account, _collateralToken, _indexToken, _isLong, _size, _entryFundingRate);
//         // feeUsd = feeUsd.add(fundingFee);
//
//         // TODO: Calculate swap fee
//         // feeUsd = feeUsd.add(swapFee);
//
//         uint256 feeTokens = vault.usdToTokenMin(_collateralToken, feeUsd);
//
//         return (feeUsd, feeTokens);
//     }
//
//     function _getPositionFee(
//         address _manager,
//         uint256 _sizeDelta,
//         uint256 _leverage,
//         bool _isLimitOrder
//     ) internal view returns (uint256 fee) {
//         uint256 tollRatio;
//         if (_isLimitOrder) {
//             tollRatio = uint256(
//                 positionManagerConfigData[_manager].makerTollRatio
//             );
//         } else {
//             tollRatio = uint256(
//                 positionManagerConfigData[_manager].takerTollRatio
//             );
//         }
//         if (tollRatio != 0) {
//             uint256 openNotional = _sizeDelta * _leverage;
//             fee = openNotional / tollRatio;
//         }
//         return fee;
//     }
//
//     function getRequestKey(address _account, uint256 _index) public pure returns (bytes32) {
//         return keccak256(abi.encodePacked(_account, _index));
//     }
//
//     function receiveFromOtherBlockchain(
//         address _manager,
//         address _trader,
//         uint256 _totalAmount,
//         uint256 _busdBonusAmount
//     ) external {
//         require(msg.sender == address(futuresAdapter), "only futures adapter");
//         insuranceFund.withdraw(
//             _manager,
//             _trader,
//             _totalAmount,
//             _busdBonusAmount
//         );
//     }
//
//     function _swap(address[] memory _path, address _receiver) internal returns (uint256) {
//         require(_path.length == 2, "invalid _path.length");
//         return _vaultSwap(_path[0], _path[1], _minOut, _receiver);
//     }
//
//     function _vaultSwap(address _tokenIn, address _tokenOut, address _receiver) internal returns (uint256) {
//         uint256 amountOut = IVault(vault).swap(_tokenIn, _tokenOut, _receiver);
//         //        require(amountOut >= _minOut, "insufficient amountOut");
//         return amountOut;
//     }
//
//     function _validateQuantity(
//         address _manager,
//         uint256 _quantity,
//         bool _isCloseOrder
//     ) internal view {
//         ManagerData memory managerConfigData = positionManagerConfigData[_manager];
//
//         // not validate minimumOrderQuantity if it's a close order
//         if (!_isCloseOrder) {
//             require(_quantity >= managerConfigData.minimumOrderQuantity, Errors.VL_INVALID_QUANTITY);
//         }
//         if (managerConfigData.stepBaseSize != 0) {
//             uint256 remainder = _quantity %
//             (10 ** 18 / managerConfigData.stepBaseSize);
//             require(remainder, Errors.VL_INVALID_QUANTITY);
//         }
//     }
//
//     function _validateExecutionOrCancellation(uint256 _positionBlockNumber) internal view {
//         require(isPositionKeeper[msg.sender], "403");
//         require(_positionBlockNumber <= block.number, "time");
//     }
//
//     function _validateMaxGlobalSize(address _indexToken, bool _isLong, uint256 _sizeDelta) internal view {
//         if (_sizeDelta == 0) {
//             return;
//         }
//
//         if (_isLong) {
//             uint256 maxGlobalLongSize = maxGlobalLongSizes[_indexToken];
//             if (maxGlobalLongSize > 0 && IVault(vault).guaranteedUsd(_indexToken).add(_sizeDelta) > maxGlobalLongSize) {
//                 revert("max longs exceeded");
//             }
//         } else {
//             uint256 maxGlobalShortSize = maxGlobalShortSizes[_indexToken];
//             if (maxGlobalShortSize > 0 && IVault(vault).globalShortSizes(_indexToken).add(_sizeDelta) > maxGlobalShortSize) {
//                 revert("max shorts exceeded");
//             }
//         }
//     }
//
//     //******************************************************************************************************************
//     // ONLY OWNER FUNCTIONS
//     //******************************************************************************************************************
//
//     function updateInsuranceFund(address _address) external onlyOwner {
//         insuranceFund = IInsuranceFund(_address);
//     }
//
//     function setPositionManagerConfigData(
//         address _positionManager,
//         uint24 _takerTollRatio,
//         uint24 _makerTollRatio,
//         uint32 _basicPoint,
//         uint40 _baseBasicPoint,
//         uint16 _contractPrice,
//         uint8 _assetRfiPercent,
//         uint80 _minimumOrderQuantity,
//         uint32 _stepBaseSize
//     ) public onlyOwner {
//         require(_positionManager != address(0), Errors.VL_EMPTY_ADDRESS);
//         positionManagerConfigData[_positionManager]
//         .takerTollRatio = _takerTollRatio;
//         positionManagerConfigData[_positionManager]
//         .makerTollRatio = _makerTollRatio;
//         positionManagerConfigData[_positionManager].basicPoint = _basicPoint;
//         positionManagerConfigData[_positionManager]
//         .baseBasicPoint = _baseBasicPoint;
//         positionManagerConfigData[_positionManager]
//         .contractPrice = _contractPrice;
//         positionManagerConfigData[_positionManager]
//         .assetRfiPercent = _assetRfiPercent;
//         positionManagerConfigData[_positionManager]
//         .minimumOrderQuantity = _minimumOrderQuantity;
//         positionManagerConfigData[_positionManager]
//         .stepBaseSize = _stepBaseSize;
//     }
//
//     function updateManagerTakerTollRatio(
//         address _positionManager,
//         uint24 _takerTollRatio
//     ) public onlyOwner {
//         require(_positionManager != address(0), Errors.VL_EMPTY_ADDRESS);
//         positionManagerConfigData[_positionManager]
//         .takerTollRatio = _takerTollRatio;
//     }
//
//     function updateManagerMakerTollRatio(
//         address _positionManager,
//         uint24 _makerTollRatio
//     ) public onlyOwner {
//         require(_positionManager != address(0), Errors.VL_EMPTY_ADDRESS);
//         positionManagerConfigData[_positionManager]
//         .makerTollRatio = _makerTollRatio;
//     }
//
//     function setManagerBaseBasicPoint(
//         address _positionManager,
//         uint40 _baseBasicPoint
//     ) public onlyOwner {
//         require(_positionManager != address(0), Errors.VL_EMPTY_ADDRESS);
//         positionManagerConfigData[_positionManager]
//         .baseBasicPoint = _baseBasicPoint;
//     }
//
//     function setManagerBasicPoint(address _positionManager, uint32 _basicPoint)
//     public
//     onlyOwner
//     {
//         require(_positionManager != address(0), Errors.VL_EMPTY_ADDRESS);
//         positionManagerConfigData[_positionManager].basicPoint = _basicPoint;
//     }
//
//     function setManagerContractPrice(
//         address _positionManager,
//         uint16 _contractPrice
//     ) public onlyOwner {
//         require(_positionManager != address(0), Errors.VL_EMPTY_ADDRESS);
//         positionManagerConfigData[_positionManager]
//         .contractPrice = _contractPrice;
//     }
//
//     function setManagerAssetRFI(
//         address _positionManager,
//         uint8 _assetRfiPercent
//     ) public onlyOwner {
//         require(_positionManager != address(0), Errors.VL_EMPTY_ADDRESS);
//         positionManagerConfigData[_positionManager]
//         .assetRfiPercent = _assetRfiPercent;
//     }
//
//     function setMinimumOrderQuantity(
//         address _positionManager,
//         uint80 _minimumOrderQuantity
//     ) public onlyOwner {
//         require(_positionManager != address(0), Errors.VL_EMPTY_ADDRESS);
//         positionManagerConfigData[_positionManager]
//         .minimumOrderQuantity = _minimumOrderQuantity;
//     }
//
//     function setStepBaseSize(address _positionManager, uint32 _stepBaseSize)
//     public
//     onlyOwner
//     {
//         require(_positionManager != address(0), Errors.VL_EMPTY_ADDRESS);
//         positionManagerConfigData[_positionManager]
//         .stepBaseSize = _stepBaseSize;
//     }
//
//     function updateFuturesAdapterContract(address _futuresAdapterContract)
//     external
//     onlyOwner
//     {
//         require(_futuresAdapterContract != address(0), Errors.VL_EMPTY_ADDRESS);
//         futuresAdapter = CrosschainFunctionCallInterface(
//             _futuresAdapterContract
//         );
//     }
//
//     function updatePosiChainId(uint256 _posiChainId) external onlyOwner {
//         posiChainId = _posiChainId;
//     }
//
//     function updatePosiChainCrosschainGatewayContract(address _address)
//     external
//     onlyOwner
//     {
//         posiChainCrosschainGatewayContract = _address;
//     }
//
//     /**
//      * @dev This empty reserved space is put in place to allow future versions to add new
//      * variables without shifting down storage in the inheritance chain.
//      * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
//      */
//     uint256[49] private __gap;
// }
