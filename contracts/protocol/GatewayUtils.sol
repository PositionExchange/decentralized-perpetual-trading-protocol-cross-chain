// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
//import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../interfaces/CrosschainFunctionCallInterface.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IVaultUtils.sol";
import "../interfaces/IShortsTracker.sol";
import "../interfaces/IGatewayUtils.sol";
import "../interfaces/IFuturXGateway.sol";
import "../interfaces/IFuturXGatewayStorage.sol";
import "../interfaces/IFuturXVoucher.sol";
import "../token/interface/IWETH.sol";
import {Errors} from "./libraries/helpers/Errors.sol";
import "./libraries/TokenConfiguration.sol";

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

    uint256 constant PRICE_DECIMALS = 10 ** 12;
    uint256 constant WEI_DECIMALS = 10 ** 18;

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

    function initialize(
        address _vault,
        address _futurXGateway,
        address _futurXGatewayStorage,
        address _futurXVoucher
    ) public initializer {
        __Ownable_init();

        vault = _vault;
        futurXGateway = _futurXGateway;
        gatewayStorage = _futurXGatewayStorage;
        futurXVoucher = _futurXVoucher;

        minimumVoucherInterval = 3 days;
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

        uint256 swapFeeToken = _getSwapFee(_path, _amountInToken);
        swapFeeUsd = _tokenToUsdMin(_path[_path.length - 1], swapFeeToken);

        totalFeeUsd = positionFeeUsd.add(swapFeeUsd);
    }

    function calculateDiscountValue(
        uint256 _voucherId,
        uint256 _amountInUsd
    ) external view returns (uint256) {
        FuturXVoucher.Voucher memory voucher = IFuturXVoucher(futurXVoucher)
            .getVoucherInfo(_voucherId);

        if (voucher.voucherType == 1) {
            uint256 discountAmountUsd = (_amountInUsd * voucher.value) / 100;
            if (discountAmountUsd > voucher.maxDiscountValue) {
                discountAmountUsd = voucher.maxDiscountValue;
            }
            return discountAmountUsd;
        }

        return 0;
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

    // Swap fee is in token
    function getSwapFee(
        address[] memory _path,
        uint256 _amountInToken
    ) external view override returns (uint256) {
        return _getSwapFee(_path, _amountInToken);
    }

    function validateIncreasePosition(
        address _account,
        uint256 _msgValue,
        address[] memory _path,
        address _indexToken,
        uint256 _amountInUsd,
        uint256 _sizeDeltaToken,
        uint256 _pip,
        uint16 _leverage,
        bool _isLong,
        uint256 _voucherId
    ) public override returns (bool) {
        if (_voucherId > 0) {
            validateVoucher(_account, _voucherId, _amountInUsd);
        }
        _validate(
            _msgValue == _getExecutionFee(),
            Errors.FGWU_EXECUTION_FEE_MISMATCHED
        );
        _validate(
            _path.length == 1 || _path.length == 2,
            Errors.FGWU_INVALID_PATH_LENGTH
        );
        // TODO: Consider move this to manager config
        _validate(_leverage > 1, Errors.FGWU_MIN_LEVERAGE_NOT_REACHED);

        address collateralToken = _path[_path.length - 1];
        validateCollateral(_account, collateralToken, _indexToken, _isLong);
        validateSize(_indexToken, _sizeDeltaToken, false);
        validateTokens(collateralToken, _indexToken, _isLong);
        // TODO: Client should validate this to save gas
        validateReservedAmount(
            _indexToken,
            collateralToken,
            _sizeDeltaToken,
            _amountInUsd,
            _pip,
            _leverage,
            _isLong
        );

        return true;
    }

    function validateDecreasePosition(
        address _account,
        uint256 _msgValue,
        address[] memory _path,
        address _indexToken,
        uint256 _sizeDeltaToken,
        bool _isLong
    ) public override returns (bool) {
        _validate(
            _msgValue == _getExecutionFee(),
            Errors.FGWU_EXECUTION_FEE_MISMATCHED
        );
        _validate(
            _path.length == 1 || _path.length == 2,
            Errors.FGWU_INVALID_PATH_LENGTH
        );

        address collateralToken = _path[0];
        validateCollateral(_account, collateralToken, _indexToken, _isLong);
        validateSize(_indexToken, _sizeDeltaToken, true);
        validateTokens(collateralToken, _indexToken, _isLong);

        return true;
    }

    function validateUpdateCollateral(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) external override returns (bool) {
        validateTokens(_collateralToken, _indexToken, _isLong);
        validateCollateral(_account, _collateralToken, _indexToken, _isLong);
        return true;
    }

    function validateVoucher(
        address _account,
        uint256 _voucherId,
        uint256 _amountInUsd
    ) public returns (bool) {
        FuturXVoucher.Voucher memory voucher = IFuturXVoucher(futurXVoucher)
            .getVoucherInfo(_voucherId);
        _validate(voucher.isActive, Errors.FGWU_VOUCHER_IS_INACTIVE);
        _validate(
            voucher.expiredTime > block.timestamp,
            Errors.FGWU_VOUCHER_IS_EXPIRED
        );
        _validate(
            lastVoucherUsage[_account] + minimumVoucherInterval <=
                block.timestamp,
            Errors.FGWU_VOUCHER_MINIMUM_TIME_NOT_MET
        );

        uint256 priceExponent = 10 ** 30;
        if (voucher.voucherType == 1) {
            _validate(
                _amountInUsd >= 10 * priceExponent,
                Errors.FGWU_V1_INSUFFICIENT_AMOUNT_01
            );
            if (voucher.maxDiscountValue >= 100 * priceExponent) {
                _validate(
                    _amountInUsd >= 20 * priceExponent,
                    Errors.FGWU_V1_INSUFFICIENT_AMOUNT_02
                );
            }
        } else {
            revert("invalid voucher type");
        }

        return true;
    }

    function validateTokens(
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) public view override returns (bool) {
        TokenConfiguration.Data memory cTokenCfg = IVault(vault)
            .getTokenConfiguration(_collateralToken);

        if (_isLong) {
            _validate(
                _collateralToken == _indexToken,
                Errors.FGWU_COLLATERAL_AND_INDEX_MISMATCHED
            );
            _validate(
                cTokenCfg.isWhitelisted,
                Errors.FGWU_COLLATERAL_NOT_WHITELISTED_01
            );
            _validate(
                !cTokenCfg.isStableToken,
                Errors.FGWU_COLLATERAL_MUST_NOT_BE_STABLE
            );
            return true;
        }

        _validate(
            cTokenCfg.isWhitelisted,
            Errors.FGWU_COLLATERAL_NOT_WHITELISTED_02
        );
        _validate(
            cTokenCfg.isStableToken,
            Errors.FGWU_COLLATERAL_MUST_BE_STABLE
        );

        TokenConfiguration.Data memory iTokenCfg = IVault(vault)
            .getTokenConfiguration(_indexToken);

        _validate(
            !iTokenCfg.isStableToken,
            Errors.FGWU_INDEX_TOKEN_MUST_NOT_BE_STABLE
        );
        _validate(
            iTokenCfg.isShortableToken,
            Errors.FGWU_INDEX_TOKEN_MUST_BE_SHORTABLE
        );

        return true;
    }

    function validateCollateral(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) public returns (bool) {
        PositionInfo.Data memory position = IVault(vault).getPositionInfo(
            _account,
            _indexToken,
            _isLong
        );
        if (
            position.reservedAmount > 0 &&
            position.collateralToken != address(0)
        ) {
            _validate(
                position.collateralToken == _collateralToken,
                Errors.FGWU_INVALID_POSITION_COLLATERAL
            );
            return true;
        }

        IFuturXGatewayStorage.PendingCollateral
            memory pendingCollateral = IFuturXGatewayStorage(gatewayStorage)
                .getPendingCollateral(_account, _indexToken);
        if (pendingCollateral.count > 0) {
            _validate(
                _collateralToken == pendingCollateral.collateral,
                Errors.FGWU_INVALID_PENDING_COLLATERAL
            );
        }
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
            _validate(
                _sizeDelta >= managerConfigData.minimumOrderQuantity,
                Errors.FGWU_MINIMUM_SIZE_NOT_REACHED
            );
        }
        if (managerConfigData.stepBaseSize != 0) {
            uint256 remainder = _sizeDelta %
                (WEI_DECIMALS / managerConfigData.stepBaseSize);
            _validate(remainder == 0, Errors.FGWU_INVALID_STEP_BASE_SIZE);
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

    function validateReservedAmount(
        address _indexToken,
        address _collateralToken,
        uint256 _sizeDeltaToken,
        uint256 _amountInUsd,
        uint256 _pip,
        uint256 _leverage,
        bool _isLong
    ) public view returns (bool) {
        // Calculate entry price
        // If limit => pip > 0
        uint256 entryPrice = calculateEntryPrice(
            _indexToken,
            _sizeDeltaToken,
            _amountInUsd,
            _pip,
            _leverage
        );
        _sizeDeltaToken = _isLong
            ? _sizeDeltaToken
            : entryPrice.mul(_sizeDeltaToken).div(WEI_DECIMALS);

        uint256 availableReservedAmount = IVault(vault)
            .getAvailableReservedAmount(_collateralToken);
        availableReservedAmount = IVault(vault).adjustDecimalToUsd(
            _collateralToken,
            availableReservedAmount
        );

        _validate(
            availableReservedAmount >= _sizeDeltaToken,
            Errors.FGWU_INSUFFICIENT_RESERVED_AMOUNT
        );
        return true;
    }

    function calculateEntryPrice(
        address _indexToken,
        uint256 _sizeDeltaToken,
        uint256 _amountInUsd,
        uint256 _pip,
        uint256 _leverage
    ) public view returns (uint256) {
        ManagerData memory managerConfigData = positionManagerConfigData[
            _indexToken
        ];

        if (_pip > 0) {
            return (_pip * WEI_DECIMALS) / managerConfigData.basicPoint;
        }

        return
            (((_amountInUsd / PRICE_DECIMALS) * _leverage) * WEI_DECIMALS) /
            _sizeDeltaToken;
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
        _validate(_positionManager != address(0), Errors.VL_EMPTY_ADDRESS);
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

    function _getSwapFee(
        address[] memory _path,
        uint256 _amountInToken
    ) internal view returns (uint256) {
        if (_path.length == 1) {
            return 0;
        }
        return IVault(vault).getSwapFee(_path[0], _path[1], _amountInToken);
    }

    function _getBorrowFee(
        address _account,
        address _collateral,
        address _indexToken,
        bool _isLong
    ) internal view returns (uint256 borrowingFeeUsd) {
        return
            IVault(vault).getBorrowingFee(
                _account,
                _collateral,
                _indexToken,
                _isLong
            );
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

    function _tokenToUsdMin(
        address _token,
        uint256 _tokenAmount
    ) internal view returns (uint256) {
        return IVault(vault).tokenToUsdMin(_token, _tokenAmount);
    }

    function setFuturXVoucher(address _address) external onlyOwner {
        futurXVoucher = _address;
    }

    function setFuturXGatewayStorage(address _address) external onlyOwner {
        gatewayStorage = _address;
    }

    function _validate(bool _condition, string memory _errorCode) private view {
        require(_condition, _errorCode);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
    address public futurXVoucher;
    mapping(address => uint256) public lastVoucherUsage;
    uint256 public minimumVoucherInterval;
    address public gatewayStorage;
}
