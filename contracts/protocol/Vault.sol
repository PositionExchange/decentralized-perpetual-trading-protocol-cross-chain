pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts/utils/StorageSlot.sol";

import "./libraries/TokenConfiguration.sol";
import "./libraries/VaultInfo.sol";
import "./libraries/PositionInfo.sol";
import {Errors} from "./libraries/helpers/Errors.sol";

import "../interfaces/IVault.sol";
import "../token/interface/IUSDP.sol";
import "../interfaces/IVaultUtils.sol";
import "../interfaces/IVaultPriceFeed.sol";
import {IFeeStrategy} from "../strategyFeeRebate/interfaces/IFeeStrategy.sol";

contract Vault is IVault, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using TokenConfiguration for TokenConfiguration.Data;
    using VaultInfo for VaultInfo.Data;
    using PositionInfo for PositionInfo.Data;

    uint256 public constant BORROWING_RATE_PRECISION = 1000000;
    uint256 public constant MAX_FEE_BASIS_POINTS = 500; // 5%
    uint256 public constant MIN_BORROWING_RATE_INTERVAL = 1 hours;
    uint256 public constant MAX_BORROWING_RATE_FACTOR = 10000; // 1%
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant DEAFULT_DECIMALS = 18;
    uint256 public constant WEI_DECIMALS = 10 ** 18;

    IVaultPriceFeed private _priceFeed;
    IVaultUtils private _vaultUtils;

    address public usdp;
    uint256 public totalTokenWeight;
    uint256 public override mintBurnFeeBasisPoints;
    uint256 public override swapFeeBasisPoints;
    uint256 public override stableSwapFeeBasisPoints;
    uint256 public override marginFeeBasisPoints;
    uint256 public override taxBasisPoints;
    uint256 public override stableTaxBasisPoints;

    bool public override hasDynamicFees;
    bool public override inManagerMode;
    bool public override isSwapEnabled;

    // TODO: Update this config to 8 hours
    uint256 public override borrowingRateInterval;
    uint256 public override borrowingRateFactor;
    uint256 public override stableBorrowingRateFactor;

    // mapping(address => bool) public whitelistTokens;
    mapping(address => bool) public whitelistCaller;
    mapping(address => uint256) public tokenBalances;
    // mapping(address => uint256) public tokenDecimals;
    mapping(address => TokenConfiguration.Data) public tokenConfigurations;
    mapping(address => VaultInfo.Data) public vaultInfo;

    // bufferAmounts allows specification of an amount to exclude from swaps
    // this can be used to ensure a certain amount of liquidity is available for leverage positions
    mapping(address => uint256) public override bufferAmounts;

    address[] public whitelistedTokens;
    uint256 public minProfitTime;
    /* mapping(address => uint256) public feeReserves; */
    /* mapping(address => uint256) public usdpAmounts; */
    /* mapping(address => uint256) public poolAmounts; */
    /* mapping(address => uint256) public reservedAmounts; */

    mapping(address => uint256) public override globalShortSizes;
    mapping(address => uint256) public override globalShortAveragePrices;
    mapping(address => uint256) public override maxGlobalShortSizes;

    // cumulativeBorrowingRates tracks the  rates based on utilization
    mapping(address => uint256) public override cumulativeBorrowingRates;
    // lastBorrowingRateTimes tracks the last time borrowing rate was updated for a token
    mapping(address => uint256) public override lastBorrowingRateTimes;

    // positionInfo tracks all open positions entry borrowing rates
    mapping(bytes32 => PositionInfo.Data) public positionInfo;

    //    mapping(address => uint256) public debtAmount;
    mapping(address => uint256) public debtAmountUsd;

    // guaranteedUsd tracks the amount of USD that is "guaranteed" by opened leverage positions
    // this value is used to calculate the redemption values for selling of USDG
    // this is an estimated amount, it is possible for the actual guaranteed value to be lower
    // in the case of sudden price decreases, the guaranteed value should be corrected
    // after liquidations are carried out
    mapping(address => uint256) private _guaranteedUsd;

    address public futurXGateway;

    uint256 public maxGasPrice;

    modifier onlyWhitelistToken(address token) {
        _validate(
            tokenConfigurations[token].isWhitelisted,
            Errors.V_TOKEN_NOT_WHITELISTED
        );
        _;
    }

    modifier onlyWhitelistCaller() {
        if (inManagerMode) {
            _validate(
                whitelistCaller[msg.sender],
                Errors.V_CALLER_NOT_WHITELISTED
            );
        }
        _;
    }

    modifier onlyGovOrOwner() {
        _validate(
            msg.sender == getGov() || msg.sender == owner(),
            "V: not gov"
        );
        _;
    }

    modifier onlyFuturXGateway(address _account) {
        _validate(_account == futurXGateway, Errors.V_ONLY_FUTURX_GATEWAY);
        _;
    }

    event BuyUSDP(
        address account,
        address token,
        uint256 tokenAmount,
        uint256 usdgAmount,
        uint256 feeBasisPoints
    );
    event SellUSDP(
        address account,
        address token,
        uint256 usdgAmount,
        uint256 tokenAmount,
        uint256 feeBasisPoints
    );
    event Swap(
        address account,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 amountOutAfterFees,
        uint256 feeBasisPoints
    );
    event CollectFees(uint256 positionFee, uint256 borrowFee, uint256 totalFee);

    event IncreaseUsdgAmount(address token, uint256 amount);
    event DecreaseUsdgAmount(address token, uint256 amount);
    event IncreasePoolAmount(address token, uint256 amount);
    event DecreasePoolAmount(address token, uint256 amount);
    event IncreaseReservedAmount(address token, uint256 amount);
    event DecreaseReservedAmount(address token, uint256 amount);
    event IncreaseGuaranteedUsd(address token, uint256 amount);
    event DecreaseGuaranteedUsd(address token, uint256 amount);
    event IncreaseFeeReserves(address token, uint256 amount);
    event IncreasePositionReserves(uint256 amount);
    event DecreasePositionReserves(uint256 amount);
    event IncreaseDebtAmount(address account, uint256 amount);
    event DecreaseDebtAmount(address account, uint256 amount);

    event WhitelistCallerChanged(address account, bool oldValue, bool newValue);
    event UpdateBorrowingRate(address token, uint256 borrowingRate);

    function initialize(
        address vaultUtils_,
        address vaultPriceFeed_,
        address usdp_
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init();

        _vaultUtils = IVaultUtils(vaultUtils_);
        _priceFeed = IVaultPriceFeed(vaultPriceFeed_);
        usdp = usdp_;

        mintBurnFeeBasisPoints = 100;
        // 1%
        swapFeeBasisPoints = 30;
        // 0.3%
        stableSwapFeeBasisPoints = 4;
        // 0.04%
        marginFeeBasisPoints = 10;
        // 0.1%
        taxBasisPoints = 50;
        // 0.5%
        stableTaxBasisPoints = 20;
        // 0.2%

        hasDynamicFees = false;
        inManagerMode = false;
        isSwapEnabled = true;

        borrowingRateInterval = 5 minutes;
        borrowingRateFactor = 600;
        stableBorrowingRateFactor = 600;
    }

    function increasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _entryPrice,
        uint256 _sizeDeltaToken,
        bool _isLong,
        uint256 _feeUsd
    ) external override onlyFuturXGateway(msg.sender) nonReentrant {
        _validateGasPrice();

        _updateCumulativeBorrowingRate(_collateralToken, _indexToken);
        bytes32 key = getPositionInfoKey(_account, _indexToken, _isLong);
        {
            _setCollateralToken(key, _collateralToken);
            uint256 borrowingFee = _getBorrowingFee(
                _account,
                _collateralToken,
                _indexToken,
                _isLong
            );
            borrowingFee =
                borrowingFee -
                _usingStrategy(_account, borrowingFee);
            _increaseDebtAmount(_account, borrowingFee);
            _updatePositionEntryBorrowingRate(key, _collateralToken);
        }

        uint256 collateralDeltaToken = _transferIn(_collateralToken);
        uint256 collateralDeltaUsd = tokenToUsdMin(
            _collateralToken,
            collateralDeltaToken
        );
        _validate(
            collateralDeltaUsd >= _feeUsd,
            Errors.V_COLLATERAL_LESS_THAN_FEE
        );

        _increaseFeeReserves(_collateralToken, _feeUsd);

        _sizeDeltaToken = adjustDecimalToToken(
            _collateralToken,
            _sizeDeltaToken
        );
        uint256 reservedAmountDelta = _increasePositionReservedAmount(
            key,
            _sizeDeltaToken,
            _entryPrice,
            _isLong
        );
        _increaseReservedAmount(_collateralToken, reservedAmountDelta);

        uint256 sizeDelta = tokenToUsdMin(_collateralToken, _sizeDeltaToken);
        if (_isLong) {
            // guaranteedUsd stores the sum of (position.size - position.collateral) for all positions
            // if a fee is charged on the collateral then guaranteedUsd should be increased by that fee amount
            // since (position.size - position.collateral) would have increased by `fee`
            _increaseGuaranteedUsd(_collateralToken, sizeDelta.add(_feeUsd));
            _decreaseGuaranteedUsd(_collateralToken, collateralDeltaUsd);
            // treat the deposited collateral as part of the pool
            _increasePoolAmount(_collateralToken, collateralDeltaToken);
            // fees need to be deducted from the pool since fees are deducted from position.collateral
            // and collateral is treated as part of the pool
            _decreasePoolAmount(
                _collateralToken,
                usdToTokenMin(_collateralToken, _feeUsd)
            );
            return;
        }

        uint256 price = _isLong
            ? getMaxPrice(_indexToken)
            : getMinPrice(_indexToken);

        if (globalShortSizes[_indexToken] == 0) {
            globalShortAveragePrices[_indexToken] = price;
        } else {
            globalShortAveragePrices[
                _indexToken
            ] = getNextGlobalShortAveragePrice(_indexToken, price, sizeDelta);
        }

        _increaseGlobalShortSize(_indexToken, sizeDelta);
    }

    function decreasePosition(
        address _trader,
        address _collateralToken,
        address _indexToken,
        uint256 _entryPrice,
        uint256 _sizeDeltaToken,
        bool _isLong,
        address _receiver,
        uint256 _amountOutUsdAfterFees,
        uint256 _feeUsd
    )
        external
        override
        onlyFuturXGateway(msg.sender)
        nonReentrant
        returns (uint256)
    {
        _validateGasPrice();

        return
            _decreasePosition(
                _trader,
                _collateralToken,
                _indexToken,
                _entryPrice,
                _sizeDeltaToken,
                _isLong,
                _receiver,
                _amountOutUsdAfterFees,
                _feeUsd
            );
    }

    function _decreasePosition(
        address _trader,
        address _collateralToken,
        address _indexToken,
        uint256 _entryPrice,
        uint256 _sizeDeltaToken,
        bool _isLong,
        address _receiver,
        uint256 _amountOutAfterFeesUsd,
        uint256 _feeUsd
    ) private returns (uint256) {
        _updateCumulativeBorrowingRate(_collateralToken, _indexToken);
        uint256 borrowingFee = _getBorrowingFee(
            _trader,
            _collateralToken,
            _indexToken,
            _isLong
        );
        _feeUsd = _feeUsd - _usingStrategy(_trader, _feeUsd + borrowingFee);
        borrowingFee = borrowingFee - _usingStrategy(_trader, borrowingFee);
        emit CollectFees(_feeUsd, borrowingFee, _feeUsd.add(borrowingFee));

        bytes32 key = getPositionInfoKey(_trader, _indexToken, _isLong);
        _updatePositionEntryBorrowingRate(key, _collateralToken);

        if (_amountOutAfterFeesUsd > 0) {
            uint256 prevDebt = _getDebtAmount(_trader);
            uint256 nextDebt = prevDebt + borrowingFee;

            if (_amountOutAfterFeesUsd > nextDebt) {
                _decreaseDebtAmount(_trader, prevDebt);
                _amountOutAfterFeesUsd -= nextDebt;
            } else {
                _decreaseDebtAmount(_trader, _amountOutAfterFeesUsd);
                _amountOutAfterFeesUsd = 0;
            }
        } else {
            _increaseDebtAmount(_trader, borrowingFee);
        }

        _feeUsd = _feeUsd.add(borrowingFee);

        // Add fee to feeReserves open
        _increaseFeeReserves(_collateralToken, _feeUsd);

        _sizeDeltaToken = adjustDecimalToToken(
            _collateralToken,
            _sizeDeltaToken
        );
        {
            uint256 reservedAmountDelta = _decreasePositionReservedAmount(
                key,
                _sizeDeltaToken,
                _entryPrice,
                _isLong
            );
            _decreaseReservedAmount(_collateralToken, reservedAmountDelta);
        }

        uint256 sizeDelta = tokenToUsdMin(_collateralToken, _sizeDeltaToken);
        if (_isLong) {
            _decreaseGuaranteedUsd(_collateralToken, sizeDelta);
        } else {
            _decreaseGlobalShortSize(_indexToken, sizeDelta);
        }

        uint256 _amountOutUsd = _amountOutAfterFeesUsd.add(_feeUsd);
        if (_amountOutUsd == 0) {
            return 0;
        }

        if (_isLong) {
            uint256 amountOutToken = usdToTokenMin(
                _collateralToken,
                _amountOutUsd
            );
            _decreasePoolAmount(_collateralToken, amountOutToken);
        }

        uint256 amountOutAfterFeesToken = usdToTokenMin(
            _collateralToken,
            _amountOutAfterFeesUsd
        );
        _transferOut(_collateralToken, amountOutAfterFeesToken, _receiver);
        return amountOutAfterFeesToken;
    }

    // TODO: refactor later using _decreasePosition function
    function liquidatePosition(
        address _trader,
        address _indexToken,
        uint256 _positionSize,
        uint256 _positionMargin,
        bool _isLong
    ) external override onlyFuturXGateway(msg.sender) nonReentrant {
        bytes32 key = getPositionInfoKey(_trader, _indexToken, _isLong);
        address collateralToken = positionInfo[key].collateralToken;

        _updateCumulativeBorrowingRate(collateralToken, _indexToken);

        uint256 borrowingFee = _getBorrowingFee(
            _trader,
            collateralToken,
            _indexToken,
            _isLong
        );

        uint256 positionAmountUsd = tokenToUsdMin(
            collateralToken,
            _positionMargin
        );
        if (borrowingFee >= positionAmountUsd) {
            borrowingFee = positionAmountUsd;
        }
        _increaseFeeReserves(collateralToken, borrowingFee);
        _decreaseReservedAmount(
            collateralToken,
            positionInfo[key].reservedAmount
        );
        _decreasePoolAmount(
            collateralToken,
            usdToTokenMin(collateralToken, borrowingFee)
        );

        if (_isLong) {
            _decreaseGuaranteedUsd(collateralToken, _positionSize);
        } else {
            _decreaseGlobalShortSize(_indexToken, _positionSize);
        }

        delete positionInfo[key];
    }

    function addCollateral(
        address _account,
        address[] memory _path,
        address _indexToken,
        bool _isLong,
        uint256 _feeToken
    ) external override onlyFuturXGateway(msg.sender) nonReentrant {
        address collateralToken = _path[_path.length - 1];
        bytes32 key = getPositionInfoKey(_account, _indexToken, _isLong);
        uint256 amountInToken = _transferIn(collateralToken);
        if (_isLong) {
            _increasePoolAmount(collateralToken, amountInToken);
        }
        _updateCumulativeBorrowingRate(collateralToken, _indexToken);

        if (_feeToken > 0) {
            _increaseFeeReservesToken(collateralToken, _feeToken);
        }
    }

    function removeCollateral(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _amountInToken
    ) external override onlyFuturXGateway(msg.sender) nonReentrant {
        if (_isLong) {
            _decreasePoolAmount(_collateralToken, _amountInToken);
        }
        _updateCumulativeBorrowingRate(_collateralToken, _indexToken);
        _transferOut(_collateralToken, _amountInToken, msg.sender);
    }

    function _decreaseGlobalShortSize(address _token, uint256 _amount) private {
        uint256 size = globalShortSizes[_token];
        if (_amount > size) {
            globalShortSizes[_token] = 0;
            return;
        }

        globalShortSizes[_token] = size.sub(_amount);
    }

    // for longs: nextAveragePrice = (nextPrice * nextSize)/ (nextSize + delta)
    // for shorts: nextAveragePrice = (nextPrice * nextSize) / (nextSize - delta)
    function getNextGlobalShortAveragePrice(
        address _indexToken,
        uint256 _nextPrice,
        uint256 _sizeDelta
    ) public view returns (uint256) {
        uint256 size = globalShortSizes[_indexToken];
        uint256 averagePrice = globalShortAveragePrices[_indexToken];
        uint256 priceDelta = averagePrice > _nextPrice
            ? averagePrice.sub(_nextPrice)
            : _nextPrice.sub(averagePrice);
        uint256 delta = size.mul(priceDelta).div(averagePrice);
        bool hasProfit = averagePrice > _nextPrice;

        uint256 nextSize = size.add(_sizeDelta);
        uint256 divisor = hasProfit ? nextSize.sub(delta) : nextSize.add(delta);

        return _nextPrice.mul(nextSize).div(divisor);
    }

    function getTokenConfiguration(
        address _token
    ) external view override returns (TokenConfiguration.Data memory) {
        return tokenConfigurations[_token];
    }

    function getPositionInfo(
        address _account,
        address _indexToken,
        bool _isLong
    ) external view override returns (PositionInfo.Data memory) {
        bytes32 key = getPositionInfoKey(_account, _indexToken, _isLong);
        return positionInfo[key];
    }

    function getAvailableReservedAmount(
        address _collateralToken
    ) external view returns (uint256) {
        VaultInfo.Data memory info = vaultInfo[_collateralToken];
        return info.poolAmounts - info.reservedAmounts;
    }

    /** OWNER FUNCTIONS **/

    function setConfigToken(
        address _token,
        uint8 _tokenDecimals,
        uint64 _minProfitBps,
        uint128 _tokenWeight,
        uint128 _maxUsdgAmount,
        bool _isStable,
        bool _isShortable
    ) public onlyGovOrOwner {
        if (!tokenConfigurations[_token].isWhitelisted) {
            whitelistedTokens.push(_token);
        }

        uint256 _totalTokenWeight = totalTokenWeight;
        // minus the old token weight
        _totalTokenWeight = _totalTokenWeight.sub(
            tokenConfigurations[_token].tokenWeight
        );
        tokenConfigurations[_token] = TokenConfiguration.Data({
            isWhitelisted: true,
            tokenDecimals: _tokenDecimals,
            minProfitBasisPoints: _minProfitBps,
            tokenWeight: _tokenWeight,
            maxUsdpAmount: _maxUsdgAmount,
            isShortableToken: _isShortable,
            isStableToken: _isStable
        });
        // reset total token weight
        totalTokenWeight = _totalTokenWeight.add(_tokenWeight);
        _validate(
            address(_vaultUtils) != address(0),
            Errors.V_MISSING_VAULT_UTILS
        );
        _validate(
            address(_priceFeed) != address(0),
            Errors.V_MISSING_VAULT_PRICE_FEED
        );
    }

    function setFees(
        uint256 _taxBasisPoints,
        uint256 _stableTaxBasisPoints,
        uint256 _mintBurnFeeBasisPoints,
        uint256 _swapFeeBasisPoints,
        uint256 _stableSwapFeeBasisPoints,
        uint256 _marginFeeBasisPoints,
        uint256 _minProfitTime,
        bool _hasDynamicFees
    ) external onlyGovOrOwner {
        _validate(_taxBasisPoints <= MAX_FEE_BASIS_POINTS, "M1");
        _validate(_stableTaxBasisPoints <= MAX_FEE_BASIS_POINTS, "M2");
        _validate(_mintBurnFeeBasisPoints <= MAX_FEE_BASIS_POINTS, "M3");
        _validate(_swapFeeBasisPoints <= MAX_FEE_BASIS_POINTS, "M4");
        _validate(_stableSwapFeeBasisPoints <= MAX_FEE_BASIS_POINTS, "M5");
        _validate(_marginFeeBasisPoints <= MAX_FEE_BASIS_POINTS, "M6");
        taxBasisPoints = _taxBasisPoints;
        stableTaxBasisPoints = _stableTaxBasisPoints;
        mintBurnFeeBasisPoints = _mintBurnFeeBasisPoints;
        swapFeeBasisPoints = _swapFeeBasisPoints;
        stableSwapFeeBasisPoints = _stableSwapFeeBasisPoints;
        marginFeeBasisPoints = _marginFeeBasisPoints;
        minProfitTime = _minProfitTime;
        hasDynamicFees = _hasDynamicFees;
    }

    function setWhitelistCaller(address caller, bool val) public onlyOwner {
        emit WhitelistCallerChanged(caller, whitelistCaller[caller], val);
        whitelistCaller[caller] = val;
    }

    function setIsSwapEnabled(
        bool _isSwapEnabled
    ) external override onlyGovOrOwner {
        isSwapEnabled = _isSwapEnabled;
    }

    function setMaxGasPrice(
        uint256 _maxGasPrice
    ) external override onlyGovOrOwner {
        maxGasPrice = _maxGasPrice;
    }

    function setUsdgAmount(
        address _token,
        uint256 _amount
    ) external override onlyGovOrOwner {
        uint256 usdgAmount = usdgAmounts(_token);
        if (_amount > usdgAmount) {
            _increaseUsdpAmount(_token, _amount.sub(usdgAmount));
            return;
        }

        _decreaseUsdpAmount(_token, usdgAmount.sub(_amount));
    }

    function setBufferAmount(
        address _token,
        uint256 _amount
    ) external override onlyGovOrOwner {
        bufferAmounts[_token] = _amount;
    }

    function setMaxGlobalShortSize(
        address _token,
        uint256 _amount
    ) external override onlyGovOrOwner {
        maxGlobalShortSizes[_token] = _amount;
    }

    function setPriceFeed(address _feed) external override onlyOwner {
        _priceFeed = IVaultPriceFeed(_feed);
    }

    function setVaultUtils(IVaultUtils _address) external override onlyOwner {
        _vaultUtils = IVaultUtils(_address);
    }

    function withdrawFees(
        address _token,
        address _receiver
    ) external override onlyGovOrOwner returns (uint256) {
        uint256 amount = uint256(vaultInfo[_token].feeReserves);
        if (amount == 0) {
            return 0;
        }
        vaultInfo[_token].feeReserves = 0;
        _transferOut(_token, amount, _receiver);
        return amount;
    }

    function setInManagerMode(
        bool _inManagerMode
    ) external override onlyGovOrOwner {
        inManagerMode = _inManagerMode;
    }

    function setBorrowingRate(
        uint256 _borrowingRateInterval,
        uint256 _borrowingRateFactor,
        uint256 _stableBorrowingRateFactor
    ) external override onlyGovOrOwner {
        _validate(
            _borrowingRateInterval >= MIN_BORROWING_RATE_INTERVAL,
            Errors.V_MIN_BORROWING_RATE_NOT_REACHED
        );
        _validate(
            _borrowingRateFactor <= MAX_BORROWING_RATE_FACTOR,
            Errors.V_MAX_BORROWING_RATE_EXCEEDED
        );
        _validate(
            _stableBorrowingRateFactor <= MAX_BORROWING_RATE_FACTOR,
            Errors.V_MAX_BORROWING_RATE_FACTOR_EXCEEDED
        );
        borrowingRateInterval = _borrowingRateInterval;
        borrowingRateFactor = _borrowingRateFactor;
        stableBorrowingRateFactor = _stableBorrowingRateFactor;
    }

    function setFuturXGateway(address _address) external onlyOwner {
        futurXGateway = _address;
    }

    function withdraw(address _recipient) external onlyGovOrOwner {
        for (uint16 i = 0; i < whitelistedTokens.length; i++) {
            IERC20Upgradeable token = IERC20Upgradeable(whitelistedTokens[i]);
            uint256 balance = token.balanceOf(address(this));
            token.safeTransfer(_recipient, balance);
        }
    }

    function setGov(address gov) external onlyOwner {
        StorageSlot.getAddressSlot(bytes32("gov.futurX")).value = gov;
    }

    function setFeeStrategy(address applyFeeStrategy) external onlyOwner {
        StorageSlot.getAddressSlot(bytes32("fee.strategy.futurX")).value = applyFeeStrategy;
    }

    /** END OWNER FUNCTIONS **/

    /// @notice Pay token to purchase USDP at the ask price
    /// @param _token the pay token
    /// @param _receiver the receiver for USDP
    function buyUSDP(
        address _token,
        address _receiver
    )
        external
        override
        onlyWhitelistCaller
        onlyWhitelistToken(_token)
        nonReentrant
        returns (uint256)
    {
        uint256 tokenAmount = _transferIn(_token);
        _validate(tokenAmount > 0, Errors.V_DEPOSIT_AMOUNT_MUST_NOT_BE_ZERO);

        _updateCumulativeBorrowingRate(_token, _token);
        uint256 price = getAskPrice(_token);

        uint256 usdpAmount = tokenAmount.mul(price).div(PRICE_PRECISION);
        usdpAmount = adjustForDecimals(usdpAmount, _token, usdp);
        _validate(usdpAmount > 0, Errors.V_USDP_AMOUNT_MUST_NOT_BE_ZERO);

        uint256 feeBasisPoints = _vaultUtils.getBuyUsdgFeeBasisPoints(
            _token,
            usdpAmount
        );

        uint256 amountAfterFees = _collectSwapFees(
            _token,
            tokenAmount,
            feeBasisPoints
        );
        uint256 mintAmount = amountAfterFees.mul(price).div(PRICE_PRECISION);
        mintAmount = adjustForDecimals(mintAmount, _token, usdp);

        _increaseUsdpAmount(_token, mintAmount);
        _increasePoolAmount(_token, amountAfterFees);

        IUSDP(usdp).mint(_receiver, mintAmount);

        emit BuyUSDP(
            _receiver,
            _token,
            tokenAmount,
            mintAmount,
            feeBasisPoints
        );
        return mintAmount;
    }

    /// @notice sell USDP for a token, at the bid price
    /// @param _token the receive token
    /// @param _receiver the receiver of the token
    function sellUSDP(
        address _token,
        address _receiver
    )
        external
        override
        onlyWhitelistCaller
        onlyWhitelistToken(_token)
        nonReentrant
        returns (uint256)
    {
        uint256 usdpAmount = _transferIn(usdp);
        _validate(usdpAmount > 0, Errors.V_DEPOSIT_AMOUNT_MUST_NOT_BE_ZERO);

        _updateCumulativeBorrowingRate(_token, _token);

        uint256 redemptionAmount = getRedemptionAmount(_token, usdpAmount);
        _validate(
            redemptionAmount > 0,
            Errors.V_REDEMPTION_AMOUNT_MUST_NOT_BE_ZERO
        );

        _decreaseUsdpAmount(_token, usdpAmount);
        _decreasePoolAmount(_token, redemptionAmount);

        IUSDP(usdp).burn(address(this), usdpAmount);

        // the _transferIn call increased the value of tokenBalances[usdg]
        // usually decreases in token balances are synced by calling _transferOut
        // however, for usdg, the tokens are burnt, so _updateTokenBalance should
        // be manually called to record the decrease in tokens
        _updateTokenBalance(usdp);

        uint256 feeBasisPoints = _vaultUtils.getSellUsdgFeeBasisPoints(
            _token,
            usdpAmount
        );
        uint256 amountOut = _collectSwapFees(
            _token,
            redemptionAmount,
            feeBasisPoints
        );
        _validate(amountOut > 0, Errors.V_WITHDRAW_AMOUNT_MUST_NOT_BE_ZERO);

        _transferOut(_token, amountOut, _receiver);

        emit SellUSDP(_receiver, _token, usdpAmount, amountOut, feeBasisPoints);
        return amountOut;
    }

    function swap(
        address _tokenIn,
        address _tokenOut,
        address _receiver
    )
        external
        override
        onlyWhitelistToken(_tokenIn)
        onlyWhitelistToken(_tokenOut)
        returns (uint256)
    {
        return _swap(_tokenIn, _tokenOut, _receiver, true);
    }

    function swapWithoutFees(
        address _tokenIn,
        address _tokenOut,
        address _receiver
    )
        external
        override
        onlyWhitelistToken(_tokenIn)
        onlyWhitelistToken(_tokenOut)
        onlyFuturXGateway(msg.sender)
        returns (uint256)
    {
        return _swap(_tokenIn, _tokenOut, _receiver, false);
    }

    function claimFund(
        address _collateralToken,
        address _account,
        bool _isLong,
        uint256 _amountOutUsd,
        address _receiver
    )
        external
        override
        onlyFuturXGateway(msg.sender)
        onlyWhitelistToken(_collateralToken)
        returns (uint256)
    {
        if (_amountOutUsd == 0) {
            return 0;
        }

        uint256 prevDebt = _getDebtAmount(_account);
        if (_amountOutUsd > prevDebt) {
            _decreaseDebtAmount(_account, prevDebt);
            _amountOutUsd -= prevDebt;
        } else {
            _decreaseDebtAmount(_account, _amountOutUsd);
            _amountOutUsd = 0;
        }

        if (_amountOutUsd == 0) {
            return 0;
        }

        uint256 amountOutToken = usdToTokenMin(_collateralToken, _amountOutUsd);
        _transferOut(_collateralToken, amountOutToken, _receiver);
        if (_isLong) {
            _decreasePoolAmount(_collateralToken, amountOutToken);
        }
        return amountOutToken;
    }

    function poolAmounts(
        address token
    ) external view override returns (uint256) {
        return uint256(vaultInfo[token].poolAmounts);
    }

    function priceFeed() external view override returns (address) {
        return address(_priceFeed);
    }

    function vaultUtils() external view override returns (address) {
        return address(_vaultUtils);
    }

    function isStableToken(
        address _token
    ) external view override returns (bool) {
        return tokenConfigurations[_token].isStableToken;
    }

    /// @notice get total usdpAmount by token
    /// @param _token the token address
    function usdpAmount(
        address _token
    ) external view override returns (uint256) {
        return vaultInfo[_token].usdpAmounts;
    }

    /// @notice get the target usdp amount weighted for a token
    /// @param _token the address of the token
    function getTargetUsdpAmount(
        address _token
    ) external view override returns (uint256) {
        uint256 supply = IERC20Upgradeable(usdp).totalSupply();
        if (supply == 0) {
            return 0;
        }
        uint256 weight = tokenConfigurations[_token].tokenWeight;
        return weight.mul(supply).div(totalTokenWeight);
    }

    function getBidPrice(
        address _token
    ) public view override returns (uint256) {
        return _priceFeed.getPrice(_token, true);
    }

    function getAskPrice(
        address _token
    ) public view override returns (uint256) {
        return _priceFeed.getPrice(_token, false);
    }

    function adjustDecimalToUsd(
        address _token,
        uint256 _amount
    ) public view returns (uint256) {
        return adjustForDecimals(_amount, _token, usdp);
    }

    function adjustDecimalToToken(
        address _token,
        uint256 _amount
    ) public view returns (uint256) {
        return adjustForDecimals(_amount, usdp, _token);
    }

    /// @notice Adjusts the amount for the decimals of the token
    /// @dev Converts the amount to the decimals of the tokenMul
    /// Eg. given convert BUSD (decimals 9) to USDP (decimals 18), amount should be amount * 10**(18-9)
    /// @param _amount the amount to be adjusted
    /// @param _tokenDiv the address of the convert token
    /// @param _tokenMul the address of the destination token
    function adjustForDecimals(
        uint256 _amount,
        address _tokenDiv,
        address _tokenMul
    ) public view returns (uint256) {
        uint256 decimalsDiv = _tokenDiv == usdp
            ? DEAFULT_DECIMALS
            : tokenConfigurations[_tokenDiv].tokenDecimals;
        uint256 decimalsMul = _tokenMul == usdp
            ? DEAFULT_DECIMALS
            : tokenConfigurations[_tokenMul].tokenDecimals;
        return _amount.mul(10 ** decimalsMul).div(10 ** decimalsDiv);
    }

    function getRedemptionAmount(
        address _token,
        uint256 _usdgAmount
    ) public view override returns (uint256) {
        uint256 price = getBidPrice(_token);
        uint256 redemptionAmount = _usdgAmount.mul(PRICE_PRECISION).div(price);
        return adjustForDecimals(redemptionAmount, usdp, _token);
    }

    function getNextBorrowingRate(
        address _token
    ) public view override returns (uint256) {
        if (
            lastBorrowingRateTimes[_token].add(borrowingRateInterval) >
            block.timestamp
        ) {
            return 0;
        }

        uint256 intervals = block
            .timestamp
            .sub(lastBorrowingRateTimes[_token])
            .div(borrowingRateInterval);
        uint256 poolAmount = vaultInfo[_token].poolAmounts;
        if (poolAmount == 0) {
            return 0;
        }

        uint256 _borrowingRateFactor = tokenConfigurations[_token].isStableToken
            ? stableBorrowingRateFactor
            : borrowingRateFactor;
        return
            _borrowingRateFactor
                .mul(vaultInfo[_token].reservedAmounts)
                .mul(intervals)
                .div(poolAmount);
    }

    function getBorrowingFee(
        address _trader,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) external view returns (uint256) {
        return
            _getBorrowingFee(_trader, _collateralToken, _indexToken, _isLong);
    }

    function getSwapFee(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external view returns (uint256) {
        uint256 priceIn = getAskPrice(_tokenIn);
        uint256 priceOut = getBidPrice(_tokenOut);
        uint256 amountOut = _amountIn.mul(priceIn).div(priceOut);
        amountOut = adjustForDecimals(amountOut, _tokenIn, _tokenOut);

        // adjust usdgAmounts by the same usdgAmount as debt is shifted between the assets
        uint256 usdgAmount = _amountIn.mul(priceIn).div(PRICE_PRECISION);
        usdgAmount = adjustForDecimals(usdgAmount, _tokenIn, usdp);

        uint256 feeBasisPoints = _vaultUtils.getSwapFeeBasisPoints(
            _tokenIn,
            _tokenOut,
            usdgAmount
        );

        uint256 afterFeeAmount = amountOut
            .mul(BASIS_POINTS_DIVISOR.sub(feeBasisPoints))
            .div(BASIS_POINTS_DIVISOR);

        return amountOut.sub(afterFeeAmount);
    }

    function getPositionInfoKey(
        address _trader,
        address _indexToken,
        bool _isLong
    ) public view returns (bytes32) {
        return keccak256(abi.encodePacked(_trader, _indexToken, _isLong));
    }

    function getUtilisation(address _token) public view returns (uint256) {
        VaultInfo.Data memory _vaultInfo = vaultInfo[_token];
        uint256 poolAmount = _vaultInfo.poolAmounts;
        if (poolAmount == 0) {
            return 0;
        }
        uint256 reservedAmounts = _vaultInfo.reservedAmounts;
        return reservedAmounts.mul(BORROWING_RATE_PRECISION).div(poolAmount);
    }

    function convert(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external view override returns (uint256) {
        uint256 priceIn = getAskPrice(_tokenIn);
        uint256 priceOut = getBidPrice(_tokenOut);
        uint256 amountOut = _amountIn.mul(priceIn).div(priceOut);
        return adjustForDecimals(amountOut, _tokenIn, _tokenOut);
    }

    /* PRIVATE FUNCTIONS */
    function _swap(
        address _tokenIn,
        address _tokenOut,
        address _receiver,
        bool _shouldCollectFee
    ) private returns (uint256) {
        _validate(isSwapEnabled, Errors.V_SWAP_IS_NOT_SUPPORTED);
        _validate(_tokenIn != _tokenOut, Errors.V_DUPLICATE_TOKENS);

        _updateCumulativeBorrowingRate(_tokenIn, _tokenIn);
        _updateCumulativeBorrowingRate(_tokenOut, _tokenOut);

        uint256 amountIn = _transferIn(_tokenIn);
        _validate(amountIn > 0, Errors.V_DEPOSIT_AMOUNT_MUST_NOT_BE_ZERO);

        uint256 priceIn = getAskPrice(_tokenIn);
        uint256 priceOut = getBidPrice(_tokenOut);

        uint256 amountOut = amountIn.mul(priceIn).div(priceOut);
        amountOut = adjustForDecimals(amountOut, _tokenIn, _tokenOut);

        uint256 amountOutAfterFees = amountOut;
        uint256 feeBasisPoints;
        if (_shouldCollectFee) {
            // adjust usdgAmounts by the same usdgAmount as debt is shifted between the assets
            uint256 usdgAmount = amountIn.mul(priceIn).div(PRICE_PRECISION);
            usdgAmount = adjustForDecimals(usdgAmount, _tokenIn, usdp);

            feeBasisPoints = _vaultUtils.getSwapFeeBasisPoints(
                _tokenIn,
                _tokenOut,
                usdgAmount
            );

            amountOutAfterFees = _collectSwapFees(
                _tokenOut,
                amountOut,
                feeBasisPoints
            );

            _increaseUsdpAmount(_tokenIn, usdgAmount);
            _decreaseUsdpAmount(_tokenOut, usdgAmount);
        }

        _increasePoolAmount(_tokenIn, amountIn);
        _decreasePoolAmount(_tokenOut, amountOut);

        // validate buffer amount
        _validate(
            vaultInfo[_tokenOut].poolAmounts >= bufferAmounts[_tokenOut],
            Errors.V_INSUFFICIENT_POOL_AMOUNT
        );

        _transferOut(_tokenOut, amountOutAfterFees, _receiver);

        emit Swap(
            _receiver,
            _tokenIn,
            _tokenOut,
            amountIn,
            amountOut,
            amountOutAfterFees,
            feeBasisPoints
        );

        return amountOutAfterFees;
    }

    function _updateCumulativeBorrowingRate(
        address _collateralToken,
        address _indexToken
    ) private {
        bool shouldUpdate = _vaultUtils.updateCumulativeBorrowingRate(
            _collateralToken,
            _indexToken
        );
        if (!shouldUpdate) {
            return;
        }

        if (lastBorrowingRateTimes[_collateralToken] == 0) {
            lastBorrowingRateTimes[_collateralToken] = block
                .timestamp
                .div(borrowingRateInterval)
                .mul(borrowingRateInterval);
            return;
        }

        if (
            lastBorrowingRateTimes[_collateralToken].add(
                borrowingRateInterval
            ) > block.timestamp
        ) {
            return;
        }

        uint256 borrowingRate = getNextBorrowingRate(_collateralToken);
        cumulativeBorrowingRates[_collateralToken] = cumulativeBorrowingRates[
            _collateralToken
        ].add(borrowingRate);
        lastBorrowingRateTimes[_collateralToken] = block
            .timestamp
            .div(borrowingRateInterval)
            .mul(borrowingRateInterval);

        emit UpdateBorrowingRate(
            _collateralToken,
            cumulativeBorrowingRates[_collateralToken]
        );
    }

    function _updatePositionEntryBorrowingRate(
        bytes32 _key,
        address _collateralToken
    ) private {
        positionInfo[_key].setEntryBorrowingRates(
            cumulativeBorrowingRates[_collateralToken]
        );
    }

    function _setCollateralToken(
        bytes32 _key,
        address _collateralToken
    ) private {
        positionInfo[_key].setCollateralToken(_collateralToken);
    }

    function _getBorrowingFee(
        address _trader,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) private view returns (uint256) {
        bytes32 _key = getPositionInfoKey(_trader, _indexToken, _isLong);
        PositionInfo.Data memory _positionInfo = positionInfo[_key];
        uint256 borrowingFee = _vaultUtils.getBorrowingFee(
            _collateralToken,
            tokenToUsdMin(_collateralToken, _positionInfo.reservedAmount),
            _positionInfo.entryBorrowingRates
        );
        return borrowingFee;
    }

    function _transferIn(address _token) private returns (uint256) {
        uint256 prevBalance = tokenBalances[_token];
        uint256 nextBalance = IERC20Upgradeable(_token).balanceOf(
            address(this)
        );
        tokenBalances[_token] = nextBalance;
        return nextBalance.sub(prevBalance);
    }

    function _transferOut(
        address _token,
        uint256 _amount,
        address _receiver
    ) private {
        if (_amount == 0) {
            return;
        }
        uint256 prevBalance = tokenBalances[_token];
        _validate(prevBalance >= _amount, Errors.V_INSUFFICIENT_BALANCE);
        IERC20Upgradeable(_token).safeTransfer(_receiver, _amount);
        tokenBalances[_token] = IERC20Upgradeable(_token).balanceOf(
            address(this)
        );
    }

    /// Calculate and collect swap fees
    /// @param _token the token to collect fees
    /// @param _amount the amount to collect
    /// @param _feeBasisPoints the fee rate
    /// Eg. given _feeBasisPoints = 100 (1% or 100/10000), _amount = 1000, the fee is 10, the amount after fee is 990
    function _collectSwapFees(
        address _token,
        uint256 _amount,
        uint256 _feeBasisPoints
    ) private returns (uint256) {
        uint256 afterFeeAmount = _amount
            .mul(BASIS_POINTS_DIVISOR.sub(_feeBasisPoints))
            .div(BASIS_POINTS_DIVISOR);

        uint256 feeAmount = _amount.sub(afterFeeAmount);
        // cr_increaseUsdpAmount
        _increaseFeeReservesToken(_token, feeAmount);
        // emit CollectSwapFees(_token, tokenToUsdMin(_token, feeAmount), feeAmount);
        return afterFeeAmount;
    }

    /// Increase usdp amount for a token
    /// @dev this function may reverted if the total amount for a token exceeds the maximum amount for a token
    /// @param _token the token to increase
    /// @param _amount the amount to increase
    function _increaseUsdpAmount(address _token, uint256 _amount) private {
        vaultInfo[_token].increaseUsdpAmount(
            _amount,
            tokenConfigurations[_token].getMaxUsdpAmount()
        );
        emit IncreaseUsdgAmount(_token, _amount);
    }

    /// Decrease usdp amount for a token
    /// @param _token the usdp amount map to a token
    /// @param _amount the usdp amount
    function _decreaseUsdpAmount(address _token, uint256 _amount) private {
        uint256 value = vaultInfo[_token].usdpAmounts;
        // since USDP can be minted using multiple assets
        // it is possible for the USDP debt for a single asset to be less than zero
        // the USDP debt is capped to zero for this case
        if (value <= _amount) {
            vaultInfo[_token].usdpAmounts = 0;
            emit DecreaseUsdgAmount(_token, value);
            return;
        }
        vaultInfo[_token].subUsdp(_amount);
        emit DecreaseUsdgAmount(_token, _amount);
    }

    /// Increase the pool amount for a token
    /// @param _token the token address
    /// @param _amount the deposited amount after fees
    function _increasePoolAmount(address _token, uint256 _amount) private {
        vaultInfo[_token].addPoolAmount(_amount);
        uint256 balance = IERC20Upgradeable(_token).balanceOf(address(this));
        _validate(
            vaultInfo[_token].poolAmounts <= balance,
            Errors.V_INSUFFICIENT_POOL_AMOUNT
        );
        emit IncreasePoolAmount(_token, _amount);
    }

    function _decreasePoolAmount(address _token, uint256 _amount) private {
        vaultInfo[_token].subPoolAmount(_amount);
        emit DecreasePoolAmount(_token, _amount);
    }

    function _increaseReservedAmount(address _token, uint256 _amount) private {
        vaultInfo[_token].addReservedAmount(_amount);
        emit IncreaseReservedAmount(_token, _amount);
    }

    function _decreaseReservedAmount(address _token, uint256 _amount) private {
        vaultInfo[_token].subReservedAmount(_amount);
        emit DecreaseReservedAmount(_token, _amount);
    }

    function _increasePositionReservedAmount(
        bytes32 _key,
        uint256 _amount,
        uint256 _entryPrice,
        bool _isLong
    ) private returns (uint256 delta) {
        delta = _isLong ? _amount : _entryPrice.mul(_amount).div(WEI_DECIMALS);
        _increasePositionReservedAmount(_key, delta);
    }

    function _increasePositionReservedAmount(
        bytes32 _key,
        uint256 _amount
    ) private {
        positionInfo[_key].addReservedAmount(_amount);
        emit IncreasePositionReserves(_amount);
    }

    function _decreasePositionReservedAmount(
        bytes32 _key,
        uint256 _amount,
        uint256 _entryPrice,
        bool _isLong
    ) private returns (uint256 delta) {
        if (_isLong) {
            delta = _amount;
            return _decreasePositionReservedAmount(_key, delta);
        }

        if (_entryPrice == 0) {
            delta = positionInfo[_key].reservedAmount;
            return _decreasePositionReservedAmount(_key, delta);
        }

        delta = _entryPrice.mul(_amount).div(WEI_DECIMALS);
        return _decreasePositionReservedAmount(_key, delta);
    }

    function _decreasePositionReservedAmount(
        bytes32 _key,
        uint256 _amount
    ) private returns (uint256) {
        emit DecreasePositionReserves(_amount);
        return positionInfo[_key].subReservedAmount(_amount);
    }

    function _increaseGuaranteedUsd(
        address _token,
        uint256 _usdAmount
    ) private {
        _guaranteedUsd[_token] = _guaranteedUsd[_token].add(_usdAmount);
        emit IncreaseGuaranteedUsd(_token, _usdAmount);
    }

    function _decreaseGuaranteedUsd(
        address _token,
        uint256 _usdAmount
    ) private {
        uint256 currentGuaranteedUsd = _guaranteedUsd[_token];
        if (_usdAmount > currentGuaranteedUsd) {
            _usdAmount = currentGuaranteedUsd;
        }
        _guaranteedUsd[_token] = currentGuaranteedUsd.sub(_usdAmount);
        emit DecreaseGuaranteedUsd(_token, _usdAmount);
    }

    function _increaseFeeReserves(
        address _collateralToken,
        uint256 _feeUsd
    ) private {
        uint256 feeToken = usdToTokenMin(_collateralToken, _feeUsd);
        _increaseFeeReservesToken(_collateralToken, feeToken);
    }

    function _increaseFeeReservesToken(
        address _collateralToken,
        uint256 _feeToken
    ) private {
        vaultInfo[_collateralToken].addFees(_feeToken);
        emit IncreaseFeeReserves(_collateralToken, _feeToken);
    }

    function _getDebtAmount(address _account) private returns (uint256) {
        return debtAmountUsd[_account];
    }

    function _increaseDebtAmount(address _account, uint256 _amount) private {
        debtAmountUsd[_account] += _amount;
        emit IncreaseDebtAmount(_account, _amount);
    }

    function _decreaseDebtAmount(address _account, uint256 _amount) private {
        uint256 debt = debtAmountUsd[_account];
        if (_amount > debt) {
            _amount = debt;
        }
        debtAmountUsd[_account] -= _amount;
        emit DecreaseDebtAmount(_account, _amount);
    }

    function _updateTokenBalance(address _token) private {
        uint256 nextBalance = IERC20Upgradeable(_token).balanceOf(
            address(this)
        );
        tokenBalances[_token] = nextBalance;
    }

    function getFeeBasisPoints(
        address _token,
        uint256 _usdpDelta,
        uint256 _feeBasisPoints,
        uint256 _taxBasisPoints,
        bool _increment
    ) external view override returns (uint256) {
        uint256 feesBasisPoints = _vaultUtils.getFeeBasisPoints(
            _token,
            _usdpDelta,
            _feeBasisPoints,
            _taxBasisPoints,
            _increment
        );
        return feesBasisPoints;
    }

    function allWhitelistedTokensLength()
        external
        view
        override
        returns (uint256)
    {
        return whitelistedTokens.length;
    }

    function allWhitelistedTokens(
        uint256 i
    ) external view override returns (address) {
        return whitelistedTokens[i];
    }

    function stableTokens(
        address _token
    ) external view override returns (bool) {
        return tokenConfigurations[_token].isStableToken;
    }

    function shortableTokens(
        address _token
    ) external view override returns (bool) {
        return tokenConfigurations[_token].isShortableToken;
    }

    function feeReserves(
        address _token
    ) external view override returns (uint256) {
        return uint256(vaultInfo[_token].feeReserves);
    }

    function tokenDecimals(
        address _token
    ) external view override returns (uint256) {
        return uint256(tokenConfigurations[_token].tokenDecimals);
    }

    function tokenWeights(
        address _token
    ) external view override returns (uint256) {
        return uint256(tokenConfigurations[_token].tokenWeight);
    }

    function guaranteedUsd(
        address _token
    ) external view override returns (uint256) {
        return _guaranteedUsd[_token];
    }

    function reservedAmounts(
        address _token
    ) external view override returns (uint256) {
        return uint256(vaultInfo[_token].reservedAmounts);
    }

    // @deprecated use usdpAmount
    function usdgAmounts(
        address _token
    ) public view override returns (uint256) {
        return uint256(vaultInfo[_token].usdpAmounts);
    }

    function usdpAmounts(address _token) external view returns (uint256) {
        return uint256(vaultInfo[_token].usdpAmounts);
    }

    function maxUsdgAmounts(
        address _token
    ) external view override returns (uint256) {
        return uint256(tokenConfigurations[_token].getMaxUsdpAmount());
    }

    function tokenToUsdMin(
        address _token,
        uint256 _tokenAmount
    ) public view returns (uint256) {
        if (_tokenAmount == 0) {
            return 0;
        }
        uint256 price = getMinPrice(_token);
        uint256 decimals = tokenConfigurations[_token].tokenDecimals;
        return _tokenAmount.mul(price).div(10 ** decimals);
    }

    function tokenToUsdMax(
        address _token,
        uint256 _tokenAmount
    ) public view returns (uint256) {
        if (_tokenAmount == 0) {
            return 0;
        }
        uint256 price = getMaxPrice(_token);
        uint256 decimals = tokenConfigurations[_token].tokenDecimals;
        return _tokenAmount.mul(price).div(10 ** decimals);
    }

    function tokenToUsdMinWithAdjustment(
        address _token,
        uint256 _tokenAmount
    ) public view returns (uint256) {
        uint256 usdAmount = tokenToUsdMin(_token, _tokenAmount);
        return adjustForDecimals(usdAmount, usdp, _token);
    }

    function usdToTokenMax(
        address _token,
        uint256 _usdAmount
    ) public view returns (uint256) {
        if (_usdAmount == 0) {
            return 0;
        }
        return usdToToken(_token, _usdAmount, getMinPrice(_token));
    }

    function usdToTokenMinWithAdjustment(
        address _token,
        uint256 _usdAmount
    ) public view returns (uint256) {
        uint256 tokenAmount = usdToTokenMin(_token, _usdAmount);
        return adjustForDecimals(tokenAmount, _token, usdp);
    }

    function usdToTokenMin(
        address _token,
        uint256 _usdAmount
    ) public view returns (uint256) {
        if (_usdAmount == 0) {
            return 0;
        }
        return usdToToken(_token, _usdAmount, getMaxPrice(_token));
    }

    function usdToToken(
        address _token,
        uint256 _usdAmount,
        uint256 _price
    ) public view returns (uint256) {
        if (_usdAmount == 0) {
            return 0;
        }
        uint256 decimals = tokenConfigurations[_token].tokenDecimals;
        return _usdAmount.mul(10 ** decimals).div(_price);
    }

    function getMaxPrice(
        address _token
    ) public view override returns (uint256) {
        return IVaultPriceFeed(_priceFeed).getPrice(_token, true);
    }

    function getMinPrice(
        address _token
    ) public view override returns (uint256) {
        return IVaultPriceFeed(_priceFeed).getPrice(_token, false);
    }

    function isWhitelistedTokens(
        address _token
    ) external view override returns (bool) {
        return tokenConfigurations[_token].isWhitelisted;
    }

    function _usingStrategy(
        address user,
        uint256 amount
    ) internal returns (uint256) {
        return IFeeStrategy(getFeeStrategy()).usingStrategy(user, amount);
    }

    function _increaseGlobalShortSize(
        address _token,
        uint256 _amount
    ) internal {
        globalShortSizes[_token] = globalShortSizes[_token].add(_amount);

        uint256 maxSize = maxGlobalShortSizes[_token];
        if (maxSize != 0) {
            _validate(
                globalShortSizes[_token] <= maxSize,
                Errors.V_MAX_SHORTS_EXCEEDED
            );
        }
    }

    // we have this validation as a function instead of a modifier to reduce contract size
    function _validateGasPrice() private view {
        if (maxGasPrice == 0) {
            return;
        }
        _validate(tx.gasprice <= maxGasPrice, Errors.V_MAX_GAS_PRICE_EXCEEDED);
    }

    function _validate(bool _condition, string memory _errorCode) private view {
        require(_condition, _errorCode);
    }

    function getGov() public view returns (address) {
        return StorageSlot.getAddressSlot(bytes32("gov.futurX")).value;
    }

    function getFeeStrategy() public view returns (address) {
        return StorageSlot.getAddressSlot(bytes32("fee.strategy.futurX")).value;
    }

    function test() public view returns (bool) {
        return true;
    }
}
