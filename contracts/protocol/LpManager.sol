pragma solidity ^0.8.2;

import "../interfaces/ILpManager.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IMintable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract LpManager is ILpManager {
    using SafeMath for uint256;
    IERC20 public plpToken;
    IERC20 public usdp;
    IVault public vault;

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

    function getAumInUsdp(
        bool maximise
    ) external view override returns (uint256) {}

    function lastAddedAt(
        address _account
    ) external override returns (uint256) {}

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
      // TODO implement
    }

    function _addLiquidity(address _fundingAccount, address _account, address _token, uint256 _amount, uint256 _minUsdp, uint256 _minGlp) private returns (uint256) {
      require(_amount > 0, "LpManager: invalid _amount");

      // calculate aum before buyUSDG
      uint256 aumInUsdp = getTotalAssetValueInUsdp(true);
      uint256 plpSupply = plpToken.totalSupply();

      IERC20(_token).transferFrom(_fundingAccount, address(vault), _amount);
      uint256 usdpAmount = vault.buyUSDP(_token, address(this));
      require(usdpAmount >= _minUsdp, "LpManager: insufficient USDP output");

      uint256 mintAmount = aumInUsdp == 0 ? usdpAmount : usdpAmount.mul(plpSupply).div(aumInUsdp);
      require(mintAmount >= _minGlp, "LpManager: insufficient PLP output");

      IMintable(address(plpToken)).mint(_account, mintAmount);

      // lastAddedAt[_account] = block.timestamp;
      emit AddLiquidity(_account, _token, _amount, aumInUsdp, plpSupply, usdpAmount, mintAmount);
      return mintAmount;
    }


    function _removeLiquidity(address _account, address _tokenOut, uint256 _plpAmount, uint256 _minOut, address _receiver) private returns (uint256) {
      require(_plpAmount > 0, "GlpManager: invalid _glpAmount");
      // require(lastAddedAt[_account].add(cooldownDuration) <= block.timestamp, "GlpManager: cooldown duration not yet passed");

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

