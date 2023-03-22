pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./libraries/TokenConfiguration.sol";
import "./libraries/VaultInfo.sol";

import "../interfaces/IVault.sol";
import "../token/interface/IUSDP.sol";
import "../interfaces/IVaultUtils.sol";
import "../interfaces/IVaultPriceFeed.sol";

contract Vault is IVault, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using TokenConfiguration for TokenConfiguration.Data;
    using VaultInfo for VaultInfo.Data;

    uint256 public constant FUNDING_RATE_PRECISION = 1000000;
    uint256 public constant MIN_LEVERAGE = 10000; // 1x
    uint256 public constant USDG_DECIMALS = 18;
    uint256 public constant MAX_FEE_BASIS_POINTS = 500; // 5%
    uint256 public constant MAX_LIQUIDATION_FEE_USD = 100 * PRICE_PRECISION; // 100 USD
    uint256 public constant MIN_FUNDING_RATE_INTERVAL = 1 hours;
    uint256 public constant MAX_FUNDING_RATE_FACTOR = 10000; // 1%
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant DEAFULT_DECIMALS = 18;

    IVaultPriceFeed private _priceFeed;
    IVaultUtils private _vaultUtils;

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
    uint256 public override liquidationFeeUsd;

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

    event IncreaseUsdgAmount(address token, uint256 amount);
    event DecreaseUsdgAmount(address token, uint256 amount);
    event IncreasePoolAmount(address token, uint256 amount);
    event DecreasePoolAmount(address token, uint256 amount);
    event WhitelistCallerChanged(address account, bool oldValue, bool newValue);

    constructor(
        address vaultUtils_,
        address vaultPriceFeed_,
        address usdp_
    ) Ownable() ReentrancyGuard() {
        _vaultUtils = IVaultUtils(vaultUtils_);
        _priceFeed = IVaultPriceFeed(vaultPriceFeed_);
        usdp = usdp_;
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
        uint256 _liquidationFeeUsd,
        uint256 _minProfitTime,
        bool _hasDynamicFees
    ) external onlyOwner {
        require(_taxBasisPoints <= MAX_FEE_BASIS_POINTS, "M1");
        require(_stableTaxBasisPoints <= MAX_FEE_BASIS_POINTS, "M2");
        require(_mintBurnFeeBasisPoints <= MAX_FEE_BASIS_POINTS, "M3");
        require(_swapFeeBasisPoints <= MAX_FEE_BASIS_POINTS, "M4");
        require(_stableSwapFeeBasisPoints <= MAX_FEE_BASIS_POINTS, "M5");
        require(_marginFeeBasisPoints <= MAX_FEE_BASIS_POINTS, "M6");
        require(_liquidationFeeUsd <= MAX_LIQUIDATION_FEE_USD, "M7");
        taxBasisPoints = _taxBasisPoints;
        stableTaxBasisPoints = _stableTaxBasisPoints;
        mintBurnFeeBasisPoints = _mintBurnFeeBasisPoints;
        swapFeeBasisPoints = _swapFeeBasisPoints;
        stableSwapFeeBasisPoints = _stableSwapFeeBasisPoints;
        marginFeeBasisPoints = _marginFeeBasisPoints;
        liquidationFeeUsd = _liquidationFeeUsd;
        minProfitTime = _minProfitTime;
        hasDynamicFees = _hasDynamicFees;
    }

    function setWhitelistCaller(address caller, bool val) public onlyOwner {
        emit WhitelistCallerChanged(caller, whitelistCaller[caller], val);
        whitelistCaller[caller] = val;
    }

    function setUsdpAmount(
        address _token,
        uint256 _amount
    ) external override onlyOwner {
        // TODO implement me
        revert("Vault not implement");
    }

    function setMaxLeverage(uint256 _maxLeverage) external override onlyOwner {
        // TODO implement me
        revert("Vault not implement");
    }

    function setManager(
        address _manager,
        bool _isManager
    ) external override onlyOwner {
        // TODO implement me
        revert("Vault not implement");
    }

    function setIsSwapEnabled(bool _isSwapEnabled) external override onlyOwner {
        isSwapEnabled = _isSwapEnabled;
    }

    function setIsLeverageEnabled(
        bool _isLeverageEnabled
    ) external override onlyOwner {
        // TODO implement me
        revert("Vault not implement");
    }

    function setMaxGasPrice(uint256 _maxGasPrice) external override onlyOwner {
        // TODO implement me
        revert("Vault not implement");
    }

    function setUsdgAmount(
        address _token,
        uint256 _amount
    ) external override onlyOwner {
        // TODO implement me
        revert("Vault not implement");
    }

    function setBufferAmount(
        address _token,
        uint256 _amount
    ) external override onlyOwner {
        bufferAmounts[_token] = _amount;
    }

    function setMaxGlobalShortSize(
        address _token,
        uint256 _amount
    ) external override onlyOwner {
        // TODO implement me
        revert("Vault not implement");
    }

    function setInPrivateLiquidationMode(
        bool _inPrivateLiquidationMode
    ) external override onlyOwner {
        // TODO implement me
        revert("Vault not implement");
    }

    function setLiquidator(
        address _liquidator,
        bool _isActive
    ) external override onlyOwner {
        // TODO implement me
        revert("Vault not implement");
    }

    function setPriceFeed(address _priceFeed) external override onlyOwner {
        // TODO implement me
        revert("Vault not implement");
    }

    function setVaultUtils(
        IVaultUtils _vaultUtils
    ) external override onlyOwner {
        // TODO implement me
        revert("Vault not implement");
    }

    function withdrawFees(
        address _token,
        address _receiver
    ) external override onlyOwner returns (uint256) {
        // TODO implement me
        revert("Vault not implement");
    }

    function setInManagerMode(bool _inManagerMode) external override onlyOwner {
        inManagerMode = _inManagerMode;
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
        require(
            tokenAmount > 0,
            "Vault: transferIn token amount must be greater than 0"
        );

        // updateCumulativeFundingRate(_token, _token);
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
        require(usdpAmount > 0, "Vault: invalid usdp amount");

        // updateCumulativeFundingRate(_token, _token);

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
        require(isSwapEnabled, "Vault: swap is not supported");
        require(_tokenIn != _tokenOut, "Vault: invalid tokens");

        // TODO check if we need to update cumulative funding rate

        /* updateCumulativeFundingRate(_tokenIn, _tokenIn); */
        /* updateCumulativeFundingRate(_tokenOut, _tokenOut); */

        uint256 amountIn = _transferIn(_tokenIn);
        require(amountIn > 0, "Vault: invalid amountIn");

        uint256 priceIn = getAskPrice(_tokenIn);
        uint256 priceOut = getBidPrice(_tokenOut);

        uint256 amountOut = amountIn.mul(priceIn).div(priceOut);
        amountOut = adjustForDecimals(amountOut, _tokenIn, _tokenOut);

        // adjust usdgAmounts by the same usdgAmount as debt is shifted between the assets
        uint256 usdgAmount = amountIn.mul(priceIn).div(PRICE_PRECISION);
        usdgAmount = adjustForDecimals(usdgAmount, _tokenIn, usdp);

        uint256 feeBasisPoints = _vaultUtils.getSwapFeeBasisPoints(
            _tokenIn,
            _tokenOut,
            usdgAmount
        );
        uint256 amountOutAfterFees = _collectSwapFees(
            _tokenOut,
            amountOut,
            feeBasisPoints
        );

        _increaseUsdpAmount(_tokenIn, usdgAmount);
        _decreaseUsdpAmount(_tokenOut, usdgAmount);

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
        uint256 supply = IERC20(usdp).totalSupply();
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

    /* PRIVATE FUNCTIONS */

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
        uint feesBasisPoints = _vaultUtils.getFeeBasisPoints(
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
        return uint(vaultInfo[_token].feeReserves);
    }

    function globalShortSizes(
        address _token
    ) external view override returns (uint256) {
        // TODO implement
    }

    function globalShortAveragePrices(
        address _token
    ) external view override returns (uint256) {
        //TODO implement
    }

    function maxGlobalShortSizes(
        address _token
    ) external view override returns (uint256) {
        // TODO implement
    }

    function tokenDecimals(
        address _token
    ) external view override returns (uint256) {
        return uint(tokenConfigurations[_token].tokenDecimals);
    }

    function tokenWeights(
        address _token
    ) external view override returns (uint256) {
        return uint(tokenConfigurations[_token].tokenWeight);
    }

    function guaranteedUsd(
        address _token
    ) external view override returns (uint256) {
        // TODO implement
    }

    function reservedAmounts(
        address _token
    ) external view override returns (uint256) {
        return uint(vaultInfo[_token].reservedAmounts);
    }

    // @deprecated use usdpAmount
    function usdgAmounts(
        address _token
    ) external view override returns (uint256) {
        return uint(vaultInfo[_token].usdpAmounts);
    }

    function usdpAmounts(address _token) external view returns (uint256) {
        return uint(vaultInfo[_token].usdpAmounts);
    }

    function maxUsdgAmounts(
        address _token
    ) external view override returns (uint256) {
        // TODO impment me
    }

    function tokenToUsdMin(address _token, uint256 _tokenAmount) public view returns (uint256) {
        if (_tokenAmount == 0) { return 0; }
        uint256 price = getMinPrice(_token);
        uint256 decimals = tokenConfigurations[_token].tokenDecimals;
        return _tokenAmount.mul(price).div(10 ** decimals);
    }

    function usdToTokenMax(address _token, uint256 _usdAmount) public view returns (uint256) {
        if (_usdAmount == 0) { return 0; }
        return usdToToken(_token, _usdAmount, getMinPrice(_token));
    }

    function usdToTokenMin(address _token, uint256 _usdAmount) public view returns (uint256) {
        if (_usdAmount == 0) { return 0; }
        return usdToToken(_token, _usdAmount, getMaxPrice(_token));
    }

    function usdToToken(address _token, uint256 _usdAmount, uint256 _price) public view returns (uint256) {
        if (_usdAmount == 0) { return 0; }
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

    function whitelistedTokenCount() external view override returns (uint256) {
        // TODO implement me
        revert("Vault not implemented");
    }

    function isWhitelistedTokens(
        address _token
    ) external view override returns (bool) {
        return tokenConfigurations[_token].isWhitelisted;
    }
}
