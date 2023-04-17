pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./libraries/TokenConfiguration.sol";
import "./libraries/VaultInfo.sol";
import "./libraries/PositionInfo.sol";

import "../interfaces/IVault.sol";
import "../token/interface/IUSDP.sol";
import "../interfaces/IVaultUtils.sol";
import "../interfaces/IVaultPriceFeed.sol";

contract Vault is IVault, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using TokenConfiguration for TokenConfiguration.Data;
    using VaultInfo for VaultInfo.Data;
    using PositionInfo for PositionInfo.Data;

    uint256 public constant BORROWING_RATE_PRECISION = 1000000;
    uint256 public constant MIN_LEVERAGE = 10000; // 1x
    uint256 public constant USDG_DECIMALS = 18;
    uint256 public constant MAX_FEE_BASIS_POINTS = 500; // 5%
    //    uint256 public constant MIN_BORROWING_RATE_INTERVAL = 1 hours;
    uint256 public constant MIN_BORROWING_RATE_INTERVAL = 1;
    uint256 public constant MAX_BORROWING_RATE_FACTOR = 10000; // 1%
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant PRICE_PRECISION = 10**30;
    uint256 public constant DEAFULT_DECIMALS = 18;

    IVaultPriceFeed private _priceFeed;
    IVaultUtils private _vaultUtils;
    address public futuresGateway;

    address public usdp;
    uint256 public totalTokenWeight;
    uint256 public override mintBurnFeeBasisPoints = 100; // 1%
    uint256 public override swapFeeBasisPoints = 30; // 0.3%
    uint256 public override stableSwapFeeBasisPoints = 4; // 0.04%
    uint256 public override marginFeeBasisPoints = 10; // 0.1%
    uint256 public override taxBasisPoints = 50; // 0.5%
    uint256 public override stableTaxBasisPoints = 20; // 0.2%

    bool public override hasDynamicFees = false;
    bool public override inManagerMode = false;
    bool public override isSwapEnabled = true;

    uint256 public override borrowingRateInterval = 8 hours;
    uint256 public override borrowingRateFactor = 600;
    uint256 public override stableBorrowingRateFactor = 600;

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

    modifier onlyWhitelistToken(address token) {
        require(
            tokenConfigurations[token].isWhitelisted,
            "Vault: token not in whitelist"
        );
        _;
    }

    modifier onlyWhitelistCaller() {
        if (inManagerMode) {
            require(
                whitelistCaller[msg.sender],
                "Vault: caller not in whitelist"
            );
        }
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
    event IncreaseFeeReserves(address token, uint256 amount);
    event IncreasePositionReserves(uint256 amount);
    event DecreasePositionReserves(uint256 amount);
    event IncreasePositionCollateral(uint256 amount);
    event DecreasePositionCollateral(uint256 amount);

    event WhitelistCallerChanged(address account, bool oldValue, bool newValue);
    event UpdateBorrowingRate(address token, uint256 borrowingRate);

    constructor(
        address vaultUtils_,
        address vaultPriceFeed_,
        address usdp_
    ) Ownable() ReentrancyGuard() {
        _vaultUtils = IVaultUtils(vaultUtils_);
        _priceFeed = IVaultPriceFeed(vaultPriceFeed_);
        usdp = usdp_;
    }

    function increasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _feeUsd
    ) external override nonReentrant {
        _validateCaller(_account);

        _updateCumulativeBorrowingRate(_collateralToken, _indexToken);
        bytes32 key = getPositionInfoKey(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
        _updatePositionEntryBorrowingRate(key, _collateralToken);

        uint256 collateralDelta = _transferIn(_collateralToken);
        uint256 collateralDeltaUsd = tokenToUsdMin(
            _collateralToken,
            collateralDelta
        );
        _validate(collateralDeltaUsd >= _feeUsd, 29);

        // TODO: Validate this from process chain
        // _validatePosition(position.size, position.collateral);

        // reserve tokens to pay profits on the position
        uint256 reserveDelta = usdToTokenMax(_collateralToken, _sizeDelta);
        _increaseReservedAmount(_collateralToken, reserveDelta);
        _increasePositionCollateralAmount(key, collateralDelta);
        _increasePositionReservedAmount(key, reserveDelta);

        // Add fee to feeReserves
        _increaseFeeReserves(_collateralToken, _feeUsd);

        if (_isLong) {
            // guaranteedUsd stores the sum of (position.size - position.collateral) for all positions
            // if a fee is charged on the collateral then guaranteedUsd should be increased by that fee amount
            // since (position.size - position.collateral) would have increased by `fee`
            _increaseGuaranteedUsd(_collateralToken, _sizeDelta.add(_feeUsd));
            _decreaseGuaranteedUsd(_collateralToken, collateralDeltaUsd);
            // treat the deposited collateral as part of the pool
            _increasePoolAmount(_collateralToken, collateralDelta);
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
            ] = getNextGlobalShortAveragePrice(_indexToken, price, _sizeDelta);
        }

        _increaseGlobalShortSize(_indexToken, _sizeDelta);
    }

    function decreasePosition(
        address _trader,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _amountOutUsdAfterFees,
        uint256 _feeUsd
    ) external override nonReentrant returns (uint256) {
        _validateCaller(msg.sender);

        return
            _decreasePosition(
                _trader,
                _collateralToken,
                _indexToken,
                _sizeDelta,
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
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _amountOutUsdAfterFees,
        uint256 _feeUsd
    ) private returns (uint256) {
        _updateCumulativeBorrowingRate(_collateralToken, _indexToken);
        uint256 borrowingFee = _getBorrowingFee(
            _trader,
            _collateralToken,
            _indexToken,
            _isLong
        );
        emit CollectFees(_feeUsd, borrowingFee, _feeUsd.add(borrowingFee));

        bytes32 key = getPositionInfoKey(
            _trader,
            _collateralToken,
            _indexToken,
            _isLong
        );
        _updatePositionEntryBorrowingRate(key, _collateralToken);

        if (borrowingFee > _amountOutUsdAfterFees) {
            _decreasePositionCollateralAmount(
                key,
                borrowingFee.sub(_amountOutUsdAfterFees)
            );
            _amountOutUsdAfterFees = 0;
        } else {
            _amountOutUsdAfterFees = _amountOutUsdAfterFees.sub(borrowingFee);
        }
        _feeUsd = _feeUsd.add(borrowingFee);

        // Add fee to feeReserves
        _increaseFeeReserves(_collateralToken, _feeUsd);

        uint256 reserveDelta = usdToTokenMin(_collateralToken, _sizeDelta);
        _decreaseReservedAmount(_collateralToken, reserveDelta);
        _decreasePositionReservedAmount(key, reserveDelta);

        if (_isLong) {
            _decreaseGuaranteedUsd(_collateralToken, _sizeDelta);
        } else {
            _decreaseGlobalShortSize(_indexToken, _sizeDelta);
        }

        uint256 _amountOutUsd = _amountOutUsdAfterFees.add(_feeUsd);
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

        uint256 amountOutTokenAfterFees = usdToTokenMin(
            _collateralToken,
            _amountOutUsdAfterFees
        );

        // TODO: Consider to update position info in core chain when borrowingFee greater than _amountOut
        // If not update, must compare _amountOutUsdAfterFees with remaining position collateral amount
        // Case _amountOutUsdAfterFees greater than collateral, must transfer out collateral amount,
        // else transfer _amountOutUsdAfterFees

        _transferOut(_collateralToken, amountOutTokenAfterFees, _receiver);
        return amountOutTokenAfterFees;
    }

    // TODO: refactor later using _decreasePosition function
    function liquidatePosition(
        address _trader,
        address _collateralToken,
        address _indexToken,
        uint256 _positionSize,
        bool _isLong
    ) external override nonReentrant {
        _validateCaller(msg.sender);

        _updateCumulativeBorrowingRate(_collateralToken, _indexToken);

        uint256 borrowingFee = _getBorrowingFee(
            _trader,
            _collateralToken,
            _indexToken,
            _isLong
        );

        bytes32 key = getPositionInfoKey(
            _trader,
            _collateralToken,
            _indexToken,
            _isLong
        );
        PositionInfo.Data memory _positionInfo = positionInfo[key];

        uint256 positionAmountUsd = tokenToUsdMin(
            _collateralToken,
            _positionInfo.collateralAmount
        );
        if (borrowingFee >= positionAmountUsd) {
            borrowingFee = positionAmountUsd;
        }
        _increaseFeeReserves(_collateralToken, borrowingFee);
        _decreaseReservedAmount(_collateralToken, _positionInfo.reservedAmount);
        _decreasePoolAmount(
            _collateralToken,
            usdToTokenMin(_collateralToken, borrowingFee)
        );

        if (_isLong) {
            _decreaseGuaranteedUsd(_collateralToken, _positionSize);
        } else {
            _decreaseGlobalShortSize(_indexToken, _positionSize);
        }

        delete positionInfo[key];
    }

    function addCollateral(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _amountInToken
    ) external override nonReentrant {
        _validateCaller(msg.sender);

        bytes32 key = getPositionInfoKey(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
        _increasePositionCollateralAmount(key, _amountInToken);
        _increasePoolAmount(_collateralToken, _amountInToken);
        _updateCumulativeBorrowingRate(_collateralToken, _indexToken);
    }

    function removeCollateral(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _amountInToken
    ) external override nonReentrant {
        _validateCaller(msg.sender);

        bytes32 key = getPositionInfoKey(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
        _decreasePositionCollateralAmount(key, _amountInToken);
        _decreasePoolAmount(_collateralToken, _amountInToken);
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

    /** OWNER FUNCTIONS **/

    function setConfigToken(
        address _token,
        uint8 _tokenDecimals,
        uint64 _minProfitBps,
        uint128 _tokenWeight,
        uint128 _maxUsdgAmount,
        bool _isStable,
        bool _isShortable
    ) public onlyOwner {
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
        require(address(_vaultUtils) != address(0), "Need vaultUtils");
        require(address(_priceFeed) != address(0), "Need priceFeed");
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
    ) external onlyOwner {
        require(_taxBasisPoints <= MAX_FEE_BASIS_POINTS, "M1");
        require(_stableTaxBasisPoints <= MAX_FEE_BASIS_POINTS, "M2");
        require(_mintBurnFeeBasisPoints <= MAX_FEE_BASIS_POINTS, "M3");
        require(_swapFeeBasisPoints <= MAX_FEE_BASIS_POINTS, "M4");
        require(_stableSwapFeeBasisPoints <= MAX_FEE_BASIS_POINTS, "M5");
        require(_marginFeeBasisPoints <= MAX_FEE_BASIS_POINTS, "M6");
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

    function setUsdpAmount(address _token, uint256 _amount)
        external
        override
        onlyOwner
    {
        // TODO implement me
        revert("setUsdpAmount not implement");
    }

    function setMaxLeverage(uint256 _maxLeverage) external override onlyOwner {
        // TODO implement me
        revert("setMaxLeverage not implement");
    }

    function setManager(address _manager, bool _isManager)
        external
        override
        onlyOwner
    {
        // TODO implement me
        revert("setManager not implement");
    }

    function setIsSwapEnabled(bool _isSwapEnabled) external override onlyOwner {
        isSwapEnabled = _isSwapEnabled;
    }

    function setIsLeverageEnabled(bool _isLeverageEnabled)
        external
        override
        onlyOwner
    {
        // TODO implement me
        revert("setIsLeverageEnabled not implement");
    }

    function setMaxGasPrice(uint256 _maxGasPrice) external override onlyOwner {
        // TODO implement me
        revert("setMaxGasPrice not implement");
    }

    function setUsdgAmount(address _token, uint256 _amount)
        external
        override
        onlyOwner
    {
        // TODO implement me
        revert("setUsdgAmount not implement");
    }

    function setBufferAmount(address _token, uint256 _amount)
        external
        override
        onlyOwner
    {
        bufferAmounts[_token] = _amount;
    }

    function setMaxGlobalShortSize(address _token, uint256 _amount)
        external
        override
        onlyOwner
    {
        // TODO implement me
        revert("setMaxGlobalShortSize not implement");
    }

    function setInPrivateLiquidationMode(bool _inPrivateLiquidationMode)
        external
        override
        onlyOwner
    {
        // TODO implement me
        revert("setInPrivateLiquidationMode not implement");
    }

    function setLiquidator(address _liquidator, bool _isActive)
        external
        override
        onlyOwner
    {
        // TODO implement me
        revert("setLiquidator not implement");
    }

    function setPriceFeed(address _feed) external override onlyOwner {
        _priceFeed = IVaultPriceFeed(_feed);
    }

    function setVaultUtils(IVaultUtils _address) external override onlyOwner {
        _vaultUtils = IVaultUtils(_address);
    }

    function withdrawFees(address _token, address _receiver)
        external
        override
        onlyOwner
        returns (uint256)
    {
        // TODO implement me
        revert("withdrawFees not implement");
    }

    function setInManagerMode(bool _inManagerMode) external override onlyOwner {
        inManagerMode = _inManagerMode;
    }

    function setBorrowingRate(
        uint256 _borrowingRateInterval,
        uint256 _borrowingRateFactor,
        uint256 _stableBorrowingRateFactor
    ) external override onlyOwner {
        _validate(_borrowingRateInterval >= MIN_BORROWING_RATE_INTERVAL, 10);
        _validate(_borrowingRateFactor <= MAX_BORROWING_RATE_FACTOR, 11);
        _validate(_stableBorrowingRateFactor <= MAX_BORROWING_RATE_FACTOR, 12);
        borrowingRateInterval = _borrowingRateInterval;
        borrowingRateFactor = _borrowingRateFactor;
        stableBorrowingRateFactor = _stableBorrowingRateFactor;
    }

    /** END OWNER FUNCTIONS **/

    /// @notice Pay token to purchase USDP at the ask price
    /// @param _token the pay token
    /// @param _receiver the receiver for USDP
    function buyUSDP(address _token, address _receiver)
        external
        override
        onlyWhitelistCaller
        onlyWhitelistToken(_token)
        nonReentrant
        returns (uint256)
    {
        uint256 tokenAmount = _transferIn(_token);
        require(
            tokenAmount > 0,
            "Vault: transferIn token amount must be greater than 0"
        );

        _updateCumulativeBorrowingRate(_token, _token);
        uint256 price = getAskPrice(_token);

        uint256 usdpAmount = tokenAmount.mul(price).div(PRICE_PRECISION);
        usdpAmount = adjustForDecimals(usdpAmount, _token, usdp);
        require(usdpAmount > 0, "Value: usdp amount must be greater than 0");

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
    function sellUSDP(address _token, address _receiver)
        external
        override
        onlyWhitelistCaller
        onlyWhitelistToken(_token)
        nonReentrant
        returns (uint256)
    {
        uint256 usdpAmount = _transferIn(usdp);
        require(usdpAmount > 0, "Vault: invalid usdp amount");

        _updateCumulativeBorrowingRate(_token, _token);

        uint256 redemptionAmount = getRedemptionAmount(_token, usdpAmount);
        require(redemptionAmount > 0, "Vault: Invalid redemption amount");

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
        require(amountOut > 0, "Vault: Invalid amount out");

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
        returns (uint256)
    {
        _validateCaller(msg.sender);
        return _swap(_tokenIn, _tokenOut, _receiver, false);
    }

    function poolAmounts(address token)
        external
        view
        override
        returns (uint256)
    {
        return uint256(vaultInfo[token].poolAmounts);
    }

    function priceFeed() external view override returns (address) {
        return address(_priceFeed);
    }

    function vaultUtils() external view override returns (address) {
        return address(_vaultUtils);
    }

    function isStableToken(address _token)
        external
        view
        override
        returns (bool)
    {
        return tokenConfigurations[_token].isStableToken;
    }

    /// @notice get total usdpAmount by token
    /// @param _token the token address
    function usdpAmount(address _token)
        external
        view
        override
        returns (uint256)
    {
        return vaultInfo[_token].usdpAmounts;
    }

    /// @notice get the target usdp amount weighted for a token
    /// @param _token the address of the token
    function getTargetUsdpAmount(address _token)
        external
        view
        override
        returns (uint256)
    {
        uint256 supply = IERC20(usdp).totalSupply();
        if (supply == 0) {
            return 0;
        }
        uint256 weight = tokenConfigurations[_token].tokenWeight;
        return weight.mul(supply).div(totalTokenWeight);
    }

    function getBidPrice(address _token)
        public
        view
        override
        returns (uint256)
    {
        return _priceFeed.getPrice(_token, true);
    }

    function getAskPrice(address _token)
        public
        view
        override
        returns (uint256)
    {
        return _priceFeed.getPrice(_token, false);
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
        return _amount.mul(10**decimalsMul).div(10**decimalsDiv);
    }

    function getRedemptionAmount(address _token, uint256 _usdgAmount)
        public
        view
        override
        returns (uint256)
    {
        uint256 price = getBidPrice(_token);
        uint256 redemptionAmount = _usdgAmount.mul(PRICE_PRECISION).div(price);
        return adjustForDecimals(redemptionAmount, usdp, _token);
    }

    function getNextBorrowingRate(address _token)
        public
        view
        override
        returns (uint256)
    {
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
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) public view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    _trader,
                    _collateralToken,
                    _indexToken,
                    _isLong
                )
            );
    }

    /* PRIVATE FUNCTIONS */
    function _swap(
        address _tokenIn,
        address _tokenOut,
        address _receiver,
        bool _shouldCollectFee
    ) private returns (uint256) {
        require(isSwapEnabled, "Vault: swap is not supported");
        require(_tokenIn != _tokenOut, "Vault: invalid tokens");

        _updateCumulativeBorrowingRate(_tokenIn, _tokenIn);
        _updateCumulativeBorrowingRate(_tokenOut, _tokenOut);

        uint256 amountIn = _transferIn(_tokenIn);
        require(amountIn > 0, "Vault: invalid amountIn");

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
        require(
            vaultInfo[_tokenOut].poolAmounts >= bufferAmounts[_tokenOut],
            "Vault: insufficient pool amount"
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

    function _getBorrowingFee(
        address _trader,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) private view returns (uint256) {
        bytes32 _key = getPositionInfoKey(
            _trader,
            _collateralToken,
            _indexToken,
            _isLong
        );
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
        uint256 nextBalance = IERC20(_token).balanceOf(address(this));
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
        require(prevBalance >= _amount, "Vault: insufficient amount");
        IERC20(_token).safeTransfer(_receiver, _amount);
        tokenBalances[_token] = IERC20(_token).balanceOf(address(this));
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
        vaultInfo[_token].addFees(feeAmount);
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
        uint256 balance = IERC20(_token).balanceOf(address(this));
        require(
            vaultInfo[_token].poolAmounts <= balance,
            "Vault: invalid pool amount"
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

    function _increasePositionCollateralAmount(bytes32 _key, uint256 _amount)
        private
    {
        positionInfo[_key].addCollateralAmount(_amount);
        emit IncreasePositionCollateral(_amount);
    }

    function _decreasePositionCollateralAmount(bytes32 _key, uint256 _amount)
        private
    {
        positionInfo[_key].subCollateralAmount(_amount);
        emit DecreasePositionCollateral(_amount);
    }

    function _increasePositionReservedAmount(bytes32 _key, uint256 _amount)
        private
    {
        positionInfo[_key].addReservedAmount(_amount);
        emit IncreasePositionReserves(_amount);
    }

    function _decreasePositionReservedAmount(bytes32 _key, uint256 _amount)
        private
    {
        positionInfo[_key].subReservedAmount(_amount);
        emit DecreasePositionReserves(_amount);
    }

    function _increaseGuaranteedUsd(address _token, uint256 _usdAmount)
        private
    {
        // TODO: Implement me
    }

    function _decreaseGuaranteedUsd(address _token, uint256 _usdAmount)
        private
    {
        // TODO: Implement me
    }

    function _increaseFeeReserves(address _collateralToken, uint256 _feeUsd)
        private
    {
        uint256 feeTokens = usdToTokenMin(_collateralToken, _feeUsd);
        vaultInfo[_collateralToken].addFees(feeTokens);
        emit IncreaseFeeReserves(_collateralToken, feeTokens);
    }

    function _updateTokenBalance(address _token) private {
        uint256 nextBalance = IERC20(_token).balanceOf(address(this));
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

    function allWhitelistedTokens(uint256 i)
        external
        view
        override
        returns (address)
    {
        return whitelistedTokens[i];
    }

    function stableTokens(address _token)
        external
        view
        override
        returns (bool)
    {
        return tokenConfigurations[_token].isStableToken;
    }

    function shortableTokens(address _token)
        external
        view
        override
        returns (bool)
    {
        return tokenConfigurations[_token].isShortableToken;
    }

    function feeReserves(address _token)
        external
        view
        override
        returns (uint256)
    {
        return uint256(vaultInfo[_token].feeReserves);
    }

    function tokenDecimals(address _token)
        external
        view
        override
        returns (uint256)
    {
        return uint256(tokenConfigurations[_token].tokenDecimals);
    }

    function tokenWeights(address _token)
        external
        view
        override
        returns (uint256)
    {
        return uint256(tokenConfigurations[_token].tokenWeight);
    }

    function guaranteedUsd(address _token)
        external
        view
        override
        returns (uint256)
    {
        // TODO implement
    }

    function reservedAmounts(address _token)
        external
        view
        override
        returns (uint256)
    {
        return uint256(vaultInfo[_token].reservedAmounts);
    }

    // @deprecated use usdpAmount
    function usdgAmounts(address _token)
        external
        view
        override
        returns (uint256)
    {
        return uint256(vaultInfo[_token].usdpAmounts);
    }

    function usdpAmounts(address _token) external view returns (uint256) {
        return uint256(vaultInfo[_token].usdpAmounts);
    }

    function maxUsdgAmounts(address _token)
        external
        view
        override
        returns (uint256)
    {
        // TODO impment me
    }

    function tokenToUsdMin(address _token, uint256 _tokenAmount)
        public
        view
        returns (uint256)
    {
        if (_tokenAmount == 0) {
            return 0;
        }
        uint256 price = getMinPrice(_token);
        uint256 decimals = tokenConfigurations[_token].tokenDecimals;
        return _tokenAmount.mul(price).div(10**decimals);
    }

    function tokenToUsdMinWithAdjustment(address _token, uint256 _tokenAmount)
        public
        view
        returns (uint256)
    {
        uint256 usdAmount = tokenToUsdMin(_token, _tokenAmount);
        return adjustForDecimals(usdAmount, usdp, _token);
    }

    function usdToTokenMax(address _token, uint256 _usdAmount)
        public
        view
        returns (uint256)
    {
        if (_usdAmount == 0) {
            return 0;
        }
        return usdToToken(_token, _usdAmount, getMinPrice(_token));
    }

    function usdToTokenMin(address _token, uint256 _usdAmount)
        public
        view
        returns (uint256)
    {
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
        return _usdAmount.mul(10**decimals).div(_price);
    }

    function getMaxPrice(address _token)
        public
        view
        override
        returns (uint256)
    {
        return IVaultPriceFeed(_priceFeed).getPrice(_token, true);
    }

    function getMinPrice(address _token)
        public
        view
        override
        returns (uint256)
    {
        return IVaultPriceFeed(_priceFeed).getPrice(_token, false);
    }

    function whitelistedTokenCount() external view override returns (uint256) {
        // TODO implement me
        revert("Vault not implemented");
    }

    function isWhitelistedTokens(address _token)
        external
        view
        override
        returns (bool)
    {
        return tokenConfigurations[_token].isWhitelisted;
    }

    function validateTokens(
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) external view returns (bool) {
        return _validateTokens(_collateralToken, _indexToken, _isLong);
    }

    function _increaseGlobalShortSize(address _token, uint256 _amount)
        internal
    {
        globalShortSizes[_token] = globalShortSizes[_token].add(_amount);

        uint256 maxSize = maxGlobalShortSizes[_token];
        if (maxSize != 0) {
            require(
                globalShortSizes[_token] <= maxSize,
                "Vault: max shorts exceeded"
            );
        }
    }

    function _validateCaller(address _account) private view {
        // TODO: Validate caller
    }

    function _validateTokens(
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) private view returns (bool) {
        TokenConfiguration.Data memory cTokenCfg = tokenConfigurations[
            _collateralToken
        ];

        if (_isLong) {
            _validate(_collateralToken == _indexToken, 42);
            _validate(cTokenCfg.isWhitelisted, 43);
            _validate(!cTokenCfg.isStableToken, 44);
            return true;
        }

        _validate(cTokenCfg.isWhitelisted, 45);
        _validate(cTokenCfg.isStableToken, 46);

        TokenConfiguration.Data memory iTokenCfg = tokenConfigurations[
            _indexToken
        ];
        _validate(!iTokenCfg.isStableToken, 47);
        _validate(iTokenCfg.isShortableToken, 48);

        return true;
    }

    function _validatePosition(uint256 _size, uint256 _collateral)
        private
        view
    {
        if (_size == 0) {
            _validate(_collateral == 0, 39);
            return;
        }
        _validate(_size >= _collateral, 40);
    }

    function _validate(bool _condition, uint256 _errorCode) private view {
        require(_condition, Strings.toString(_errorCode));
    }
}
