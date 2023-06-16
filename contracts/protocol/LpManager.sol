pragma solidity ^0.8.9;

import "../interfaces/ILpManager.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IMintable.sol";
import "../interfaces/IShortsTracker.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LpManager is ILpManager, Ownable {
    using SafeMath for uint256;
    IERC20 private _plpToken;
    IERC20 private _usdp;
    IVault public vault;
    IShortsTracker public shortsTracker;

    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant USDG_DECIMALS = 18;
    uint256 public constant GLP_PRECISION = 10 ** 18;
    uint256 public constant MAX_COOLDOWN_DURATION = 48 hours;
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;

    uint256 public aumAddition;
    uint256 public aumDeduction;
    uint256 public shortsTrackerAveragePriceWeight;

    uint256 public cooldownDuration;
    mapping(address => uint256) public override lastAddedAt;
    mapping(address => bool) public isHandler;

    event AddLiquidity(
        address account,
        address token,
        uint256 amount,
        uint256 aumInUsdg,
        uint256 glpSupply,
        uint256 usdgAmount,
        uint256 mintAmount
    );

    event RemoveLiquidity(
        address account,
        address token,
        uint256 glpAmount,
        uint256 aumInUsdg,
        uint256 glpSupply,
        uint256 usdgAmount,
        uint256 amountOut
    );

    modifier onlyHandler() {
        require(isHandler[msg.sender], "LpManager: only handler");
        _;
    }

    constructor(
        IERC20 plpToken_,
        IERC20 usdp_,
        IVault vault_,
        address shortsTracker_,
        uint256 cooldownDuration_
    ) {
        _plpToken = plpToken_;
        _usdp = usdp_;
        vault = vault_;
        shortsTracker = IShortsTracker(shortsTracker_);
        cooldownDuration = cooldownDuration_;
    }

    function setAumAdjustment(
        uint256 _aumAddition,
        uint256 _aumDeduction
    ) external onlyOwner {
        aumAddition = _aumAddition;
        aumDeduction = _aumDeduction;
    }

    function setVault(address _vault) external onlyOwner {
        vault = IVault(_vault);
    }

    function setCooldownDuration(uint256 _cooldownDuration) external onlyOwner {
        require(
            _cooldownDuration <= MAX_COOLDOWN_DURATION,
            "LpManager: invalid _cooldownDuration"
        );
        cooldownDuration = _cooldownDuration;
    }

    function setHandler(address _handler, bool _isActive) external onlyOwner {
        isHandler[_handler] = _isActive;
    }

    function setGov(address _gov) external onlyOwner {
        _transferOwnership(_gov);
    }

    /**
     * @notice Calculates the assets under management (AUM) of a vault in terms of USDP
     * @param maximise A boolean value indicating whether to use the maximum or minimum price for each token
     * @return The calculated AUM value in USDP as a uint256
     */
    function getAumInUsdp(
        bool maximise
    ) external view override returns (uint256) {
        uint256 aum = getAum(maximise);
        return aum.mul(10 ** USDG_DECIMALS).div(PRICE_PRECISION);
    }

    /**
     * @notice Calculates the assets under management (AUM) of a vault
     * @param maximise A boolean value indicating whether to use the maximum or minimum price for each token
     * @return The calculated AUM value as a uint256
     */
    function getAum(bool maximise) public view returns (uint256) {
        uint256 length = vault.allWhitelistedTokensLength();
        uint256 aum = aumAddition;
        uint256 shortProfits = 0;
        IVault _vault = vault;

        for (uint256 i = 0; i < length; i++) {
            address token = vault.allWhitelistedTokens(i);
            bool isWhitelisted = vault.isWhitelistedTokens(token);

            if (!isWhitelisted) {
                continue;
            }

            uint256 price = maximise
                ? _vault.getMaxPrice(token)
                : _vault.getMinPrice(token);
            uint256 poolAmount = _vault.poolAmounts(token);
            uint256 decimals = _vault.tokenDecimals(token);

            if (_vault.stableTokens(token)) {
                aum = aum.add(poolAmount.mul(price).div(10 ** decimals));
            } else {
                // add global short profit / loss
                uint256 size = _vault.globalShortSizes(token);

                if (size > 0) {
                    (uint256 delta, bool hasProfit) = getGlobalShortDelta(
                        token,
                        price,
                        size
                    );
                    if (!hasProfit) {
                        // add losses from shorts
                        aum = aum.add(delta);
                    } else {
                        shortProfits = shortProfits.add(delta);
                    }
                }

                aum = aum.add(_vault.guaranteedUsd(token));

                uint256 reservedAmount = _vault.reservedAmounts(token);
                aum = aum.add(
                    poolAmount.sub(reservedAmount).mul(price).div(
                        10 ** decimals
                    )
                );
            }
        }

        aum = shortProfits > aum ? 0 : aum.sub(shortProfits);
        return aumDeduction > aum ? 0 : aum.sub(aumDeduction);
    }

    function getGlobalShortDelta(
        address _token,
        uint256 _price,
        uint256 _size
    ) public view returns (uint256, bool) {
        uint256 averagePrice = getGlobalShortAveragePrice(_token);
        uint256 priceDelta = averagePrice > _price
            ? averagePrice.sub(_price)
            : _price.sub(averagePrice);
        uint256 delta = _size.mul(priceDelta).div(averagePrice);
        return (delta, averagePrice > _price);
    }

    function getGlobalShortAveragePrice(
        address _token
    ) public view returns (uint256) {
        IShortsTracker _shortsTracker = shortsTracker;
        if (
            address(_shortsTracker) == address(0) ||
            !_shortsTracker.isGlobalShortDataReady()
        ) {
            return vault.globalShortAveragePrices(_token);
        }

        uint256 _shortsTrackerAveragePriceWeight = shortsTrackerAveragePriceWeight;
        if (_shortsTrackerAveragePriceWeight == 0) {
            return vault.globalShortAveragePrices(_token);
        } else if (_shortsTrackerAveragePriceWeight == BASIS_POINTS_DIVISOR) {
            return _shortsTracker.globalShortAveragePrices(_token);
        }

        uint256 vaultAveragePrice = vault.globalShortAveragePrices(_token);
        uint256 shortsTrackerAveragePrice = _shortsTracker
            .globalShortAveragePrices(_token);

        return
            vaultAveragePrice
                .mul(BASIS_POINTS_DIVISOR.sub(_shortsTrackerAveragePriceWeight))
                .add(
                    shortsTrackerAveragePrice.mul(
                        _shortsTrackerAveragePriceWeight
                    )
                )
                .div(BASIS_POINTS_DIVISOR);
    }

    /// @notice Add liquidity for caller. Caller pay `_token`, receive back PLP token
    /// @param _token the pay token. eg BUSD
    /// @param _amount the amount in pay token in wei. eg 10 * 10e18
    /// @param _minUsdp min usdp in wei, the contract will revert if _minUsdp is not met
    /// @param _minPlp min plp amount in wei, the contract will revert if _minPlp is not met
    function addLiquidity(
        address _token,
        uint256 _amount,
        uint256 _minUsdp,
        uint256 _minPlp
    ) external override returns (uint256) {
        return
            _addLiquidity(
                msg.sender,
                msg.sender,
                _token,
                _amount,
                _minUsdp,
                _minPlp
            );
    }

    /// @notice add liquidity for an account, only whitelist handler can call
    /// @param _fundingAccount funding account
    /// @param _account credit account
    /// @param _token the pay token. eg BUSD
    /// @param _amount the amount in pay token in wei. eg 10 * 10e18
    /// @param _minUsdp min usdp in wei, the contract will revert if _minUsdp is not met
    /// @param _minPlp min plp amount in wei, the contract will revert if _minPlp is not met
    function addLiquidityForAccount(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount,
        uint256 _minUsdp,
        uint256 _minPlp
    ) external override onlyHandler returns (uint256) {
        return
            _addLiquidity(
                _fundingAccount,
                _account,
                _token,
                _amount,
                _minUsdp,
                _minPlp
            );
    }

    /// @notice Remove liquidity for caller
    /// Transfer back the tokenOut
    /// @param _tokenOut the receive token
    /// @param _plpAmount plp amount to remove
    /// @param _minOut minimum amount acceptable. otherwise will revert
    /// @param _receiver the addres of receiver
    function removeLiquidity(
        address _tokenOut,
        uint256 _plpAmount,
        uint256 _minOut,
        address _receiver
    ) external override returns (uint256) {
        return
            _removeLiquidity(
                msg.sender,
                _tokenOut,
                _plpAmount,
                _minOut,
                _receiver
            );
    }

    /// @notice Remove liquidity for account
    /// Transfer back the tokenOut
    /// @param _account the affected account
    /// @param _tokenOut the receive token
    /// @param _plpAmount plp amount to remove
    /// @param _minOut minimum amount acceptable. otherwise will revert
    /// @param _receiver the addres of receiver
    function removeLiquidityForAccount(
        address _account,
        address _tokenOut,
        uint256 _plpAmount,
        uint256 _minOut,
        address _receiver
    ) external override onlyHandler returns (uint256) {
        return
            _removeLiquidity(
                _account,
                _tokenOut,
                _plpAmount,
                _minOut,
                _receiver
            );
    }

    function setShortsTrackerAveragePriceWeight(
        uint256 _shortsTrackerAveragePriceWeight
    ) external override {
        // TODO imp. this
        revert("LpManager: setShortsTrackerAveragePriceWeight not implemented");
    }

    /**
     * @notice Calculates the total asset value of a vault in terms of USDP
     * @param maximise A boolean value indicating whether to use the maximum or minimum price for each token
     * @return The calculated total asset value in USDP as a uint256
     */
    function getTotalAssetValueInUsdp(
        bool maximise
    ) public view returns (uint256) {
        uint256 aum = getAum(maximise);
        return aum.mul(10 ** USDG_DECIMALS).div(PRICE_PRECISION);
    }

    function _addLiquidity(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount,
        uint256 _minUsdp,
        uint256 _minGlp
    ) private returns (uint256) {
        require(_amount > 0, "LpManager: invalid _amount");

        // calculate aum before buyUSDG
        uint256 aumInUsdp = getTotalAssetValueInUsdp(true);
        uint256 plpSupply = _plpToken.totalSupply();

        IERC20(_token).transferFrom(_fundingAccount, address(vault), _amount);
        uint256 usdpAmount = vault.buyUSDP(_token, address(this));
        require(usdpAmount >= _minUsdp, "LpManager: insufficient _usdp output");
        uint256 mintAmount = aumInUsdp == 0
            ? usdpAmount
            : usdpAmount.mul(plpSupply).div(aumInUsdp);
        require(mintAmount >= _minGlp, "LpManager: insufficient PLP output");

        IMintable(address(_plpToken)).mint(_account, mintAmount);

        lastAddedAt[_account] = block.timestamp;
        emit AddLiquidity(
            _account,
            _token,
            _amount,
            aumInUsdp,
            plpSupply,
            usdpAmount,
            mintAmount
        );
        return mintAmount;
    }

    function _removeLiquidity(
        address _account,
        address _tokenOut,
        uint256 _plpAmount,
        uint256 _minOut,
        address _receiver
    ) private returns (uint256) {
        require(_plpAmount > 0, "LpManager: invalid _glpAmount");
        require(
            lastAddedAt[_account].add(cooldownDuration) <= block.timestamp,
            "LpManager: cooldown duration not yet passed"
        );

        // calculate aum before sellUSDG
        uint256 aumInUsdp = getTotalAssetValueInUsdp(false);
        uint256 plpSupply = _plpToken.totalSupply();

        uint256 usdpAmount = _plpAmount.mul(aumInUsdp).div(plpSupply);
        uint256 usdpBalance = _usdp.balanceOf(address(this));
        if (usdpAmount > usdpBalance) {
            IMintable(address(_usdp)).mint(
                address(this),
                usdpAmount.sub(usdpBalance)
            );
        }

        IMintable(address(_plpToken)).burn(_account, _plpAmount);

        _usdp.transfer(address(vault), usdpAmount);
        uint256 amountOut = vault.sellUSDP(_tokenOut, _receiver);
        require(amountOut >= _minOut, "LpManager: insufficient output");

        emit RemoveLiquidity(
            _account,
            _tokenOut,
            _plpAmount,
            aumInUsdp,
            plpSupply,
            usdpAmount,
            amountOut
        );

        return amountOut;
    }

    function plpToken() external view override returns (address) {
        return address(_plpToken);
    }

    function usdp() external view override returns (address) {
        return address(_usdp);
    }
}
