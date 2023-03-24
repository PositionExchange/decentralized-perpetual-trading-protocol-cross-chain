pragma solidity ^0.8.2;

import "../interfaces/ILpManager.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IMintable.sol";
import "../interfaces/IShortsTracker.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "hardhat/console.sol";

contract LpManager is ILpManager, Ownable {
    using SafeMath for uint256;
    IERC20 public plpToken;
    IERC20 public usdp;
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
    mapping (address => uint256) public override lastAddedAt;

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

    constructor(
        IERC20 _plpToken,
        IERC20 _usdp,
        IVault _vault
    ) {
        plpToken = _plpToken;
        usdp = _usdp;
        vault = _vault;
    }

    function setAumAdjustment(uint256 _aumAddition, uint256 _aumDeduction) external onlyOwner {
        aumAddition = _aumAddition;
        aumDeduction = _aumDeduction;
    }
    function setCooldownDuration(uint256 _cooldownDuration) external onlyOwner() {
        require(_cooldownDuration <= MAX_COOLDOWN_DURATION, "LpManager: invalid _cooldownDuration");
        cooldownDuration = _cooldownDuration;
    }

    function getAumInUsdp(
        bool maximise
    ) external view override returns (uint256) {
        uint256 aum = getAum(maximise);
        return aum.mul(10 ** USDG_DECIMALS).div(PRICE_PRECISION);
    }

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

            uint256 price = maximise ? _vault.getMaxPrice(token) : _vault.getMinPrice(token);
            uint256 poolAmount = _vault.poolAmounts(token);
            uint256 decimals = _vault.tokenDecimals(token);

            if (_vault.stableTokens(token)) {
                aum = aum.add(poolAmount.mul(price).div(10 ** decimals));
            } else {
                // add global short profit / loss
                uint256 size = _vault.globalShortSizes(token);

                if (size > 0) {
                    (uint256 delta, bool hasProfit) = getGlobalShortDelta(token, price, size);
                    if (!hasProfit) {
                        // add losses from shorts
                        aum = aum.add(delta);
                    } else {
                        shortProfits = shortProfits.add(delta);
                    }
                }

                aum = aum.add(_vault.guaranteedUsd(token));

                uint256 reservedAmount = _vault.reservedAmounts(token);
                aum = aum.add(poolAmount.sub(reservedAmount).mul(price).div(10 ** decimals));
            }
        }

        aum = shortProfits > aum ? 0 : aum.sub(shortProfits);
        return aumDeduction > aum ? 0 : aum.sub(aumDeduction);
    }

    function getGlobalShortDelta(address _token, uint256 _price, uint256 _size) public view returns (uint256, bool) {
        uint256 averagePrice = getGlobalShortAveragePrice(_token);
        uint256 priceDelta = averagePrice > _price ? averagePrice.sub(_price) : _price.sub(averagePrice);
        uint256 delta = _size.mul(priceDelta).div(averagePrice);
        return (delta, averagePrice > _price);
    }

    function getGlobalShortAveragePrice(address _token) public view returns (uint256) {
        IShortsTracker _shortsTracker = shortsTracker;
        if (address(_shortsTracker) == address(0) || !_shortsTracker.isGlobalShortDataReady()) {
            return vault.globalShortAveragePrices(_token);
        }

        uint256 _shortsTrackerAveragePriceWeight = shortsTrackerAveragePriceWeight;
        if (_shortsTrackerAveragePriceWeight == 0) {
            return vault.globalShortAveragePrices(_token);
        } else if (_shortsTrackerAveragePriceWeight == BASIS_POINTS_DIVISOR) {
            return _shortsTracker.globalShortAveragePrices(_token);
        }

        uint256 vaultAveragePrice = vault.globalShortAveragePrices(_token);
        uint256 shortsTrackerAveragePrice = _shortsTracker.globalShortAveragePrices(_token);

        return vaultAveragePrice.mul(BASIS_POINTS_DIVISOR.sub(_shortsTrackerAveragePriceWeight))
            .add(shortsTrackerAveragePrice.mul(_shortsTrackerAveragePriceWeight))
            .div(BASIS_POINTS_DIVISOR);
    }


    function addLiquidity(
        address _token,
        uint256 _amount,
        uint256 _minUsdp,
        uint256 _minPlp
    ) external override returns (uint256) {
      return _addLiquidity(msg.sender, msg.sender, _token, _amount, _minUsdp, _minPlp);
    }

    function addLiquidityForAccount(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount,
        uint256 _minUsdp,
        uint256 _minPlp
    ) external override returns (uint256) {
      return _addLiquidity(_fundingAccount, _account, _token, _amount, _minUsdp, _minPlp);
    }

    function removeLiquidity(
        address _tokenOut,
        uint256 _plpAmount,
        uint256 _minOut,
        address _receiver
    ) external override returns (uint256) {
      return _removeLiquidity(msg.sender, _tokenOut, _plpAmount, _minOut, _receiver);
    }

    function removeLiquidityForAccount(
        address _account,
        address _tokenOut,
        uint256 _plpAmount,
        uint256 _minOut,
        address _receiver
    ) external override returns (uint256) {
      return _removeLiquidity(_account, _tokenOut, _plpAmount, _minOut, _receiver);
    }

    function setShortsTrackerAveragePriceWeight(
        uint256 _shortsTrackerAveragePriceWeight
    ) external override {}


    function getTotalAssetValueInUsdp(bool maximise) public view returns (uint256) {
      uint256 aum = getAum(maximise);
      return aum.mul(10 ** USDG_DECIMALS).div(PRICE_PRECISION);
    }

    function _addLiquidity(address _fundingAccount, address _account, address _token, uint256 _amount, uint256 _minUsdp, uint256 _minGlp) private returns (uint256) {
      require(_amount > 0, "LpManager: invalid _amount");

      // calculate aum before buyUSDG
      uint256 aumInUsdp = getTotalAssetValueInUsdp(true);
      uint256 plpSupply = plpToken.totalSupply();

      IERC20(_token).transferFrom(_fundingAccount, address(vault), _amount);
      uint256 usdpAmount = vault.buyUSDP(_token, address(this));
      require(usdpAmount >= _minUsdp, "LpManager: insufficient USDP output");
      console.log("plpSupply", plpSupply);
      uint256 mintAmount = aumInUsdp == 0 ? usdpAmount : usdpAmount.mul(plpSupply).div(aumInUsdp);
      console.log("mintAmount vs minGLP", mintAmount, _minGlp, aumInUsdp);
      require(mintAmount >= _minGlp, "LpManager: insufficient PLP output");

      IMintable(address(plpToken)).mint(_account, mintAmount);
      console.log("add liquidty block", block.timestamp, block.number);

      lastAddedAt[_account] = block.timestamp;
      emit AddLiquidity(_account, _token, _amount, aumInUsdp, plpSupply, usdpAmount, mintAmount);
      return mintAmount;
    }


    function _removeLiquidity(address _account, address _tokenOut, uint256 _plpAmount, uint256 _minOut, address _receiver) private returns (uint256) {
      require(_plpAmount > 0, "GlpManager: invalid _glpAmount");
      require(lastAddedAt[_account].add(cooldownDuration) <= block.timestamp, "LpManager: cooldown duration not yet passed");

      // calculate aum before sellUSDG
      uint256 aumInUsdp = getTotalAssetValueInUsdp(false);
      uint256 plpSupply = plpToken.totalSupply();

      uint256 usdpAmount = _plpAmount.mul(aumInUsdp).div(plpSupply);
      uint256 usdpBalance = usdp.balanceOf(address(this));
      if (usdpAmount > usdpBalance) {
          IMintable(address(usdp)).mint(address(this), usdpAmount.sub(usdpBalance));
      }

      IMintable(address(plpToken)).burn(_account, _plpAmount);

      usdp.transfer(address(vault), usdpAmount);
      uint256 amountOut = vault.sellUSDP(_tokenOut, _receiver);
      require(amountOut >= _minOut, "GlpManager: insufficient output");

      emit RemoveLiquidity(_account, _tokenOut, _plpAmount, aumInUsdp, plpSupply, usdpAmount, amountOut);

      return amountOut;
    }

}

