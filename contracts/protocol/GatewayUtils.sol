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
import "../interfaces/IGatewayUtils.sol";
import "../interfaces/IFuturXGateway.sol";
import "../token/interface/IWETH.sol";
import {Errors} from "./libraries/helpers/Errors.sol";

contract GatewayUtils is
    IGatewayUtils,
    PausableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;
    using SafeCastUpgradeable for uint256;
    using AddressUpgradeable for address;

    uint256 constant PRICE_DECIMALS = 10**12;
    uint256 constant WEI_DECIMALS = 10**18;

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

    event CollectFees(
        uint256 amountInBeforeFeeToken,
        uint256 positionFee,
        uint256 borrowFee,
        uint256 swapFee
    );

    address public vault;
    address public futurXGateway;

    mapping(address => ManagerData) public positionManagerConfigData;

    function initialize(address _vault) public initializer {
        __Ownable_init();
        vault = _vault;
    }

    function calculateMarginFees(
        address _trader,
        address[] memory _path,
        address _indexToken,
        bool _isLong,
        uint256 _amountInToken,
        uint256 _amountInUsd,
        uint256 _leverage,
        bool _isLimitOrder
    )
        external
        view
        override
        returns (
            uint256 positionFeeUsd,
            uint256 borrowingFeeUsd,
            uint256 swapFeeUsd,
            uint256 totalFeeUsd
        )
    {
        // Fee for opening and closing position
        positionFeeUsd = _getPositionFee(
            _indexToken,
            _amountInUsd,
            _leverage,
            _isLimitOrder
        );

        borrowingFeeUsd = IVault(vault).getBorrowingFee(
            _trader,
            _path[_path.length - 1],
            _indexToken,
            _isLong
        );
        borrowingFeeUsd = borrowingFeeUsd.div(PRICE_DECIMALS);

        swapFeeUsd = _getSwapFee(_path, _amountInToken);

        totalFeeUsd = positionFeeUsd.add(borrowingFeeUsd).add(swapFeeUsd);
    }

    function getPositionFee(
        address _indexToken,
        uint256 _amountInUsd,
        uint256 _leverage,
        bool _isLimitOrder
    ) external view override returns (uint256) {
        return
            _getPositionFee(
                _indexToken,
                _amountInUsd,
                _leverage,
                _isLimitOrder
            );
    }

    function getSwapFee(address[] memory _path, uint256 _amountInToken)
        external
        view
        override
        returns (uint256)
    {
        return _getSwapFee(_path, _amountInToken);
    }

    function validateIncreasePosition(
        uint256 _msgValue,
        address[] memory _path,
        address _indexToken,
        uint256 _sizeDeltaToken,
        uint16 _leverage,
        bool _isLong
    ) public override returns (bool) {
        require(_msgValue == _getExecutionFee(), "fee");
        require(_path.length == 1 || _path.length == 2, "len");
        // TODO: Consider move this to manager config
        require(_leverage > 1, "min leverage");
        validateSize(_indexToken, _sizeDeltaToken, false);
        validateToken(_path[_path.length - 1], _indexToken, _isLong);
        return true;
    }

    function validateDecreasePosition(
        uint256 _msgValue,
        address[] memory _path,
        address _indexToken,
        uint256 _sizeDeltaToken,
        bool _isLong
    ) public override returns (bool) {
        require(_msgValue == _getExecutionFee(), "fee");
        require(_path.length == 1 || _path.length == 2, "len");
        validateSize(_indexToken, _sizeDeltaToken, false);
        validateToken(_path[_path.length - 1], _indexToken, _isLong);
        return true;
    }

    function validateToken(
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) public view override returns (bool) {
        bool _isTokenValid = IVault(vault).validateTokens(
            _collateralToken,
            _indexToken,
            _isLong
        );
        require(_isTokenValid, "token invalid");
        return true;
    }

    function validateSize(
        address _indexToken,
        uint256 _sizeDelta,
        bool _isCloseOrder
    ) public view override returns (bool) {
        ManagerData memory managerConfigData = positionManagerConfigData[
            _indexToken
        ];

        // not validate minimumOrderQuantity if it's a close order
        if (!_isCloseOrder) {
            require(
                _sizeDelta >= managerConfigData.minimumOrderQuantity,
                Errors.VL_INVALID_QUANTITY
            );
        }
        if (managerConfigData.stepBaseSize != 0) {
            uint256 remainder = _sizeDelta %
                (WEI_DECIMALS / managerConfigData.stepBaseSize);
            require(remainder == 0, Errors.VL_INVALID_QUANTITY);
        }
        return true;
    }

    function validateMaxGlobalSize(
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta
    ) public view override returns (bool) {
        //        if (_sizeDelta == 0) {
        //            return;
        //        }
        //
        //        if (_isLong) {
        //            uint256 maxGlobalLongSize = maxGlobalLongSizes[_indexToken];
        //            if (
        //                maxGlobalLongSize > 0 &&
        //                IVault(vault).guaranteedUsd(_indexToken).add(_sizeDelta) >
        //                maxGlobalLongSize
        //            ) {
        //                revert("max longs exceeded");
        //            }
        //        } else {
        //            uint256 maxGlobalShortSize = maxGlobalShortSizes[_indexToken];
        //            if (
        //                maxGlobalShortSize > 0 &&
        //                IVault(vault).globalShortSizes(_indexToken).add(_sizeDelta) >
        //                maxGlobalShortSize
        //            ) {
        //                revert("max shorts exceeded");
        //            }
        //        }
        return true;
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
    ) external onlyOwner {
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

    function setFuturXGateway(address _futurXGateway) external onlyOwner {
        futurXGateway = _futurXGateway;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function _getSwapFee(address[] memory _path, uint256 _amountInToken)
        internal
        view
        returns (uint256)
    {
        return
            _path.length > 1
                ? IVault(vault).getSwapFee(_path[0], _path[1], _amountInToken)
                : 0;
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

    function _getExecutionFee() internal returns (uint256) {
        //        return IFuturXGateway(futurXGateway).executionFee();
        return 0;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}
