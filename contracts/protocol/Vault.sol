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

import "hardhat/console.sol";

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
    uint256 public override liquidationFeeUsd;

    // mapping(address => bool) public whitelistTokens;
    mapping(address => bool) public whitelistCaller;
    mapping(address => uint256) public tokenBalances;
    // mapping(address => uint256) public tokenDecimals;
    mapping(address => TokenConfiguration.Data) public tokenConfigurations;
    mapping(address => VaultInfo.Data) public vaultInfo;

    address[] public whitelistedTokens;
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
        require(whitelistCaller[msg.sender], "Vault: caller not in whitelist");
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
        /* minProfitTime = _minProfitTime; */
        hasDynamicFees = _hasDynamicFees;
    }

    function setWhitelistCaller(address caller, bool val) public onlyOwner {
        emit WhitelistCallerChanged(caller, whitelistCaller[caller], val);
        whitelistCaller[caller] = val;
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
        console.log("BUY >>> tokenAmount", tokenAmount);
        uint256 price = getAskPrice(_token);
        console.log("price", price);

        uint256 usdpAmount = tokenAmount.mul(price).div(PRICE_PRECISION);
        console.log("usdpAmount", usdpAmount);
        usdpAmount = adjustForDecimals(usdpAmount, _token, usdp);
        require(usdpAmount > 0, "Value: usdp amount must be greater than 0");

        uint256 feeBasisPoints = _vaultUtils.getBuyUsdgFeeBasisPoints(
            _token,
            usdpAmount
        );
        console.log("feeBasisPoints", feeBasisPoints);

        uint256 amountAfterFees = _collectSwapFees(
            _token,
            tokenAmount,
            feeBasisPoints
        );
        uint256 mintAmount = amountAfterFees.mul(price).div(PRICE_PRECISION);
        mintAmount = adjustForDecimals(mintAmount, _token, usdp);
        console.log("mintAmount", mintAmount);

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
        console.log("feeBasisPoints", feeBasisPoints);
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
    ) external override returns (uint256) {
        // TODO implement me
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
        console.log("getAskPrice, token", _token);
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
        return _amount.mul(10 ** (decimalsMul - decimalsDiv));
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
        console.log(
            "_collectSwapFees, _token, _amount, _feeBasisPoints",
            _token,
            _amount,
            _feeBasisPoints
        );
        uint256 afterFeeAmount = _amount
            .mul(BASIS_POINTS_DIVISOR.sub(_feeBasisPoints))
            .div(BASIS_POINTS_DIVISOR);

        uint256 feeAmount = _amount.sub(afterFeeAmount);
        console.log("feeAmount, afterFeeAmount", feeAmount, afterFeeAmount);
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
        console.log("_decreasePoolAmount, _token, _amount", _amount);
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
      console.log("Vault.getFeeBasisPoints, _usdpDelta, _feeBasisPoints", _usdpDelta, _feeBasisPoints);
      uint feesBasisPoints = _vaultUtils.getFeeBasisPoints(_token, _usdpDelta, _feeBasisPoints, _taxBasisPoints, _increment);
      console.log("Vault.getFeeBasisPoints, feesBasisPoints after", feesBasisPoints);
      return feesBasisPoints;
    }

}
