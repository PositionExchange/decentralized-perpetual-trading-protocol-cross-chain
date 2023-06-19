pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "./interfaces/IRewardTracker.sol";
import "./interfaces/IRewardRouter.sol";
import "./interfaces/IVester.sol";
import "../token/interface/IMintable.sol";
import "../token/interface/IWETH.sol";
import "../interfaces/ILpManager.sol";
import "../access/GovernableUpgradeable.sol";

contract RewardRouter is
    IRewardRouter,
    ReentrancyGuardUpgradeable,
    GovernableUpgradeable
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;
    address public weth;

    address public posi;
    address public esPosi;
    address public bnPosi;

    address public plp; // posi Liquidity Provider token

    address public stakedPosiTracker;
    address public bonusPosiTracker;
    address public feePosiTracker;

    address public override stakedPlpTracker;
    address public override feePlpTracker;

    address public plpManager;

    address public posiVester;
    address public plpVester;

    mapping(address => address) public pendingReceivers;

    event StakePosi(address account, address token, uint256 amount);
    event UnstakePosi(address account, address token, uint256 amount);

    event StakePlp(address account, uint256 amount);
    event UnstakePlp(address account, uint256 amount);

    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }

    struct ParamToken {
        address weth;
        address posi;
        address esPosi;
        address bnPosi;
        address plp;
    }

    function initialize(
        ParamToken memory _paramToken,
        address _stakedPosiTracker,
        address _bonusPosiTracker,
        address _feePosiTracker,
        address _feePlpTracker,
        address _stakedPlpTracker,
        address _plpManager,
        address _posiVester,
        address _plpVester
    ) external initializer {
        __ReentrancyGuard_init();
        __Governable_init();

        weth = _paramToken.weth;
        posi = _paramToken.posi;
        esPosi = _paramToken.esPosi;
        bnPosi = _paramToken.bnPosi;
        plp = _paramToken.plp;

        stakedPosiTracker = _stakedPosiTracker;
        bonusPosiTracker = _bonusPosiTracker;
        feePosiTracker = _feePosiTracker;
        feePlpTracker = _feePlpTracker;
        stakedPlpTracker = _stakedPlpTracker;
        plpManager = _plpManager;
        posiVester = _posiVester;
        plpVester = _plpVester;
    }

    // to help users who accidentally send their tokens to this contract
    // only gov can withdraw tokens
    function withdrawToken(
        address _token,
        address _account,
        uint256 _amount
    ) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function batchStakePosiForAccount(
        address[] memory _accounts,
        uint256[] memory _amounts
    ) external nonReentrant onlyGov {
        address _posi = posi;
        for (uint256 i = 0; i < _accounts.length; i++) {
            _stakePosi(msg.sender, _accounts[i], _posi, _amounts[i]);
        }
    }

    function stakePosiForAccount(
        address _account,
        uint256 _amount
    ) external nonReentrant onlyGov {
        _stakePosi(msg.sender, _account, posi, _amount);
    }

    function isInitialized() external view returns (bool) {
        return _getInitializedVersion() > 0;
    }

    /// @notice stake posi
    /// @param _amount the amount to stake
    function stakePosi(uint256 _amount) external nonReentrant {
        _stakePosi(msg.sender, msg.sender, posi, _amount);
    }

    /// @notice stake esPOSI
    /// @param _amount the amount to stake
    function stakeEsPosi(uint256 _amount) external nonReentrant {
        _stakePosi(msg.sender, msg.sender, esPosi, _amount);
    }

    /// @notice un stake posi
    /// @param _amount the amount to unstake
    function unstakePosi(uint256 _amount) external nonReentrant {
        _unstakePosi(msg.sender, posi, _amount, true);
    }

    /// @notice un stake esPOSI
    /// @param _amount the amount to unstake
    function unstakeEsPosi(uint256 _amount) external nonReentrant {
        _unstakePosi(msg.sender, esPosi, _amount, true);
    }

    /// @notice stake _token, mint plp, then auto stake to the pool
    /// @param _token the token to purchase plp
    /// @param _amount the amount to purchase plp
    /// @param _minUsdp min usdp, avoid slippage
    /// @param _minPlp min plp, avoid slippage
    function mintAndStakePlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdp,
        uint256 _minPlp
    ) external nonReentrant returns (uint256) {
        require(_amount > 0, "RewardRouter: invalid _amount");

        address account = msg.sender;
        uint256 plpAmount = ILpManager(plpManager).addLiquidityForAccount(
            account,
            account,
            _token,
            _amount,
            _minUsdp,
            _minPlp
        );
        IRewardTracker(feePlpTracker).stakeForAccount(
            account,
            account,
            plp,
            plpAmount
        );
        IRewardTracker(stakedPlpTracker).stakeForAccount(
            account,
            account,
            feePlpTracker,
            plpAmount
        );

        emit StakePlp(account, plpAmount);

        return plpAmount;
    }


    /// @notice stake _token, mint plp, then auto stake to the pool
    /// @param plpAmount the amount of PLP to stake
    function stakePlp(
        uint256 plpAmount
    ) external nonReentrant returns (uint256) {
        require(plpAmount > 0, "RewardRouter: invalid _amount");
        address account = msg.sender;

        IRewardTracker(feePlpTracker).stakeForAccount(
            account,
            account,
            plp,
            plpAmount
        );

        IRewardTracker(stakedPlpTracker).stakeForAccount(
            account,
            account,
            feePlpTracker,
            plpAmount
        );

        emit StakePlp(account, plpAmount);

        return plpAmount;
    }

    /// @notice stake _token, mint plp, then auto stake to the pool
    /// @param _token the token to purchase plp
    /// @param _amount the amount to purchase plp
    /// @param _minUsdp min usdp, avoid slippage
    /// @param _minPlp min plp, avoid slippage
    function mintPlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdp,
        uint256 _minPlp
    ) external nonReentrant returns (uint256) {
        require(_amount > 0, "RewardRouter: invalid _amount");

        address account = msg.sender;
        uint256 plpAmount = ILpManager(plpManager).addLiquidityForAccount(
            account,
            account,
            _token,
            _amount,
            _minUsdp,
            _minPlp
        );
        emit StakePlp(account, plpAmount);

        return plpAmount;
    }

    function mintPlpETH(
        uint256 _minUsdp,
        uint256 _minPlp
    ) external payable nonReentrant returns (uint256) {
        require(msg.value > 0, "RewardRouter: invalid msg.value");

        IWETH(weth).deposit{value: msg.value}();
        IERC20(weth).approve(plpManager, msg.value);

        address account = msg.sender;
        uint256 plpAmount = ILpManager(plpManager).addLiquidityForAccount(
            address(this),
            account,
            weth,
            msg.value,
            _minUsdp,
            _minPlp
        );

        emit StakePlp(account, plpAmount);
        return plpAmount;
    }

    /// @notice redeem plp and unstake PLP
    /// @param _tokenOut receive token
    /// @param _plpAmount plp amount
    /// @param _minOut min amount out
    /// @param _receiver receive address
    function unstakeAndRedeemPlp(
        address _tokenOut,
        uint256 _plpAmount,
        uint256 _minOut,
        address _receiver
    ) external nonReentrant returns (uint256) {
        require(_plpAmount > 0, "RewardRouter: invalid _plpAmount");

        address account = msg.sender;
        IRewardTracker(stakedPlpTracker).unstakeForAccount(
            account,
            feePlpTracker,
            _plpAmount,
            account
        );
        IRewardTracker(feePlpTracker).unstakeForAccount(
            account,
            plp,
            _plpAmount,
            account
        );
        uint256 amountOut = ILpManager(plpManager).removeLiquidityForAccount(
            account,
            _tokenOut,
            _plpAmount,
            _minOut,
            _receiver
        );

        emit UnstakePlp(account, _plpAmount);

        return amountOut;
    }

    /// @notice unstakePlp
    /// @param _plpAmount plp amount
    function unstakePlp(
        uint256 _plpAmount
    ) external nonReentrant {
        require(_plpAmount > 0, "RewardRouter: invalid _plpAmount");

        address account = msg.sender;
        IRewardTracker(stakedPlpTracker).unstakeForAccount(
            account,
            feePlpTracker,
            _plpAmount,
            account
        );
        IRewardTracker(feePlpTracker).unstakeForAccount(
            account,
            plp,
            _plpAmount,
            account
        );
        emit UnstakePlp(account, _plpAmount);
    }

    /// @notice redeem plp
    /// @param _tokenOut receive token
    /// @param _plpAmount plp amount
    /// @param _minOut min amount out
    /// @param _receiver receive address
    function redeemPlp(
        address _tokenOut,
        uint256 _plpAmount,
        uint256 _minOut,
        address _receiver
    ) external nonReentrant returns (uint256) {
        require(_plpAmount > 0, "RewardRouter: invalid _plpAmount");

        address account = msg.sender;

        uint256 amountOut = ILpManager(plpManager).removeLiquidityForAccount(
            account,
            _tokenOut,
            _plpAmount,
            _minOut,
            _receiver
        );

        emit UnstakePlp(account, _plpAmount);

        return amountOut;
    }

    /// @notice redeem plp
    /// @param _plpAmount the Plp amount to redeem
    /// @param _minOut min amount out
    /// @param _receiver receive address
    function redeemPlpETH(
        uint256 _plpAmount,
        uint256 _minOut,
        address payable _receiver
    ) external nonReentrant returns (uint256) {
        require(_plpAmount > 0, "RewardRouter: invalid _plpAmount");

        address account = msg.sender;

        uint256 amountOut = ILpManager(plpManager).removeLiquidityForAccount(
            account,
            weth,
            _plpAmount,
            _minOut,
            address(this)
        );

        IWETH(weth).withdraw(amountOut);

        _receiver.sendValue(amountOut);

        emit UnstakePlp(account, _plpAmount);

        return amountOut;
    }

    /// @notice claim rewards
    function claim() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feePosiTracker).claimForAccount(account, account);
        IRewardTracker(feePlpTracker).claimForAccount(account, account);
        IRewardTracker(stakedPosiTracker).claimForAccount(account, account);
        IRewardTracker(stakedPlpTracker).claimForAccount(account, account);
    }

    /// @notice claim esPosi
    function claimEsPosi() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(stakedPosiTracker).claimForAccount(account, account);
        IRewardTracker(stakedPlpTracker).claimForAccount(account, account);
    }

    /// @notice claim fees
    function claimFees() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feePosiTracker).claimForAccount(account, account);
        IRewardTracker(feePlpTracker).claimForAccount(account, account);
    }

    /// @notice compound rewards
    function compound() external nonReentrant {
        _compound(msg.sender);
    }

    /// @notice cound for an account. only Gov
    /// @param _account the account to compound
    function compoundForAccount(
        address _account
    ) external nonReentrant onlyGov {
        _compound(_account);
    }

    function handleRewards(
        bool _shouldClaimPosi,
        bool _shouldStakePosi,
        bool _shouldClaimEsPosi,
        bool _shouldStakeEsPosi,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external nonReentrant {
        address account = msg.sender;

        uint256 posiAmount = 0;
        if (_shouldClaimPosi) {
            uint256 posiAmount0 = IVester(posiVester).claimForAccount(
                account,
                account
            );
            uint256 posiAmount1 = IVester(plpVester).claimForAccount(
                account,
                account
            );
            posiAmount = posiAmount0.add(posiAmount1);
        }

        if (_shouldStakePosi && posiAmount > 0) {
            _stakePosi(account, account, posi, posiAmount);
        }

        uint256 esPosiAmount = 0;
        if (_shouldClaimEsPosi) {
            uint256 esPosiAmount0 = IRewardTracker(stakedPosiTracker)
                .claimForAccount(account, account);
            uint256 esPosiAmount1 = IRewardTracker(stakedPlpTracker)
                .claimForAccount(account, account);
            esPosiAmount = esPosiAmount0.add(esPosiAmount1);
        }

        if (_shouldStakeEsPosi && esPosiAmount > 0) {
            _stakePosi(account, account, esPosi, esPosiAmount);
        }

        if (_shouldStakeMultiplierPoints) {
            uint256 bnPosiAmount = IRewardTracker(bonusPosiTracker)
                .claimForAccount(account, account);
            if (bnPosiAmount > 0) {
                IRewardTracker(feePosiTracker).stakeForAccount(
                    account,
                    account,
                    bnPosi,
                    bnPosiAmount
                );
            }
        }

        if (_shouldClaimWeth) {
            if (_shouldConvertWethToEth) {
                uint256 weth0 = IRewardTracker(feePosiTracker).claimForAccount(
                    account,
                    address(this)
                );
                uint256 weth1 = IRewardTracker(feePlpTracker).claimForAccount(
                    account,
                    address(this)
                );

                uint256 wethAmount = weth0.add(weth1);
                IWETH(weth).withdraw(wethAmount);

                payable(account).sendValue(wethAmount);
            } else {
                IRewardTracker(feePosiTracker).claimForAccount(
                    account,
                    account
                );
                IRewardTracker(feePlpTracker).claimForAccount(account, account);
            }
        }
    }

    function batchCompoundForAccounts(
        address[] memory _accounts
    ) external nonReentrant onlyGov {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _compound(_accounts[i]);
        }
    }

    function signalTransfer(address _receiver) external nonReentrant {
        require(
            IERC20(posiVester).balanceOf(msg.sender) == 0,
            "RewardRouter: sender has vested tokens"
        );
        require(
            IERC20(plpVester).balanceOf(msg.sender) == 0,
            "RewardRouter: sender has vested tokens"
        );

        _validateReceiver(_receiver);
        pendingReceivers[msg.sender] = _receiver;
    }

    function acceptTransfer(address _sender) external nonReentrant {
        require(
            IERC20(posiVester).balanceOf(_sender) == 0,
            "RewardRouter: sender has vested tokens"
        );
        require(
            IERC20(plpVester).balanceOf(_sender) == 0,
            "RewardRouter: sender has vested tokens"
        );

        address receiver = msg.sender;
        require(
            pendingReceivers[_sender] == receiver,
            "RewardRouter: transfer not signalled"
        );
        delete pendingReceivers[_sender];

        _validateReceiver(receiver);
        _compound(_sender);

        uint256 stakedPosi = IRewardTracker(stakedPosiTracker).depositBalances(
            _sender,
            posi
        );
        if (stakedPosi > 0) {
            _unstakePosi(_sender, posi, stakedPosi, false);
            _stakePosi(_sender, receiver, posi, stakedPosi);
        }

        uint256 stakedEsPosi = IRewardTracker(stakedPosiTracker)
            .depositBalances(_sender, esPosi);
        if (stakedEsPosi > 0) {
            _unstakePosi(_sender, esPosi, stakedEsPosi, false);
            _stakePosi(_sender, receiver, esPosi, stakedEsPosi);
        }

        uint256 stakedBnPosi = IRewardTracker(feePosiTracker).depositBalances(
            _sender,
            bnPosi
        );
        if (stakedBnPosi > 0) {
            IRewardTracker(feePosiTracker).unstakeForAccount(
                _sender,
                bnPosi,
                stakedBnPosi,
                _sender
            );
            IRewardTracker(feePosiTracker).stakeForAccount(
                _sender,
                receiver,
                bnPosi,
                stakedBnPosi
            );
        }

        uint256 esPosiBalance = IERC20(esPosi).balanceOf(_sender);
        if (esPosiBalance > 0) {
            IERC20(esPosi).transferFrom(_sender, receiver, esPosiBalance);
        }

        uint256 plpAmount = IRewardTracker(feePlpTracker).depositBalances(
            _sender,
            plp
        );
        if (plpAmount > 0) {
            IRewardTracker(stakedPlpTracker).unstakeForAccount(
                _sender,
                feePlpTracker,
                plpAmount,
                _sender
            );
            IRewardTracker(feePlpTracker).unstakeForAccount(
                _sender,
                plp,
                plpAmount,
                _sender
            );

            IRewardTracker(feePlpTracker).stakeForAccount(
                _sender,
                receiver,
                plp,
                plpAmount
            );
            IRewardTracker(stakedPlpTracker).stakeForAccount(
                receiver,
                receiver,
                feePlpTracker,
                plpAmount
            );
        }

        IVester(posiVester).transferStakeValues(_sender, receiver);
        IVester(plpVester).transferStakeValues(_sender, receiver);
    }

    /* PRIVATE FUNCTIONS */

    function _validateReceiver(address _receiver) private view {
        require(
            IRewardTracker(stakedPosiTracker).averageStakedAmounts(_receiver) ==
                0,
            "RewardRouter: stakedPosiTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(stakedPosiTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: stakedPosiTracker.cumulativeRewards > 0"
        );

        require(
            IRewardTracker(bonusPosiTracker).averageStakedAmounts(_receiver) ==
                0,
            "RewardRouter: bonusPosiTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(bonusPosiTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: bonusPosiTracker.cumulativeRewards > 0"
        );

        require(
            IRewardTracker(feePosiTracker).averageStakedAmounts(_receiver) == 0,
            "RewardRouter: feePosiTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(feePosiTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: feePosiTracker.cumulativeRewards > 0"
        );

        require(
            IVester(posiVester).transferredAverageStakedAmounts(_receiver) == 0,
            "RewardRouter: posiVester.transferredAverageStakedAmounts > 0"
        );
        require(
            IVester(posiVester).transferredCumulativeRewards(_receiver) == 0,
            "RewardRouter: posiVester.transferredCumulativeRewards > 0"
        );

        require(
            IRewardTracker(stakedPlpTracker).averageStakedAmounts(_receiver) ==
                0,
            "RewardRouter: stakedPlpTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(stakedPlpTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: stakedPlpTracker.cumulativeRewards > 0"
        );

        require(
            IRewardTracker(feePlpTracker).averageStakedAmounts(_receiver) == 0,
            "RewardRouter: feePlpTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(feePlpTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: feePlpTracker.cumulativeRewards > 0"
        );

        require(
            IVester(plpVester).transferredAverageStakedAmounts(_receiver) == 0,
            "RewardRouter: posiVester.transferredAverageStakedAmounts > 0"
        );
        require(
            IVester(plpVester).transferredCumulativeRewards(_receiver) == 0,
            "RewardRouter: posiVester.transferredCumulativeRewards > 0"
        );

        require(
            IERC20(posiVester).balanceOf(_receiver) == 0,
            "RewardRouter: posiVester.balance > 0"
        );
        require(
            IERC20(plpVester).balanceOf(_receiver) == 0,
            "RewardRouter: plpVester.balance > 0"
        );
    }

    function _compound(address _account) private {
        _compoundPosi(_account);
        _compoundPlp(_account);
    }

    function _compoundPosi(address _account) private {
        uint256 esPosiAmount = IRewardTracker(stakedPosiTracker)
            .claimForAccount(_account, _account);
        if (esPosiAmount > 0) {
            _stakePosi(_account, _account, esPosi, esPosiAmount);
        }

        uint256 bnPosiAmount = IRewardTracker(bonusPosiTracker).claimForAccount(
            _account,
            _account
        );
        if (bnPosiAmount > 0) {
            IRewardTracker(feePosiTracker).stakeForAccount(
                _account,
                _account,
                bnPosi,
                bnPosiAmount
            );
        }
    }

    function _compoundPlp(address _account) private {
        uint256 esPosiAmount = IRewardTracker(stakedPlpTracker).claimForAccount(
            _account,
            _account
        );
        if (esPosiAmount > 0) {
            _stakePosi(_account, _account, esPosi, esPosiAmount);
        }
    }

    function _stakePosi(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount
    ) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        IRewardTracker(stakedPosiTracker).stakeForAccount(
            _fundingAccount,
            _account,
            _token,
            _amount
        );
        IRewardTracker(bonusPosiTracker).stakeForAccount(
            _account,
            _account,
            stakedPosiTracker,
            _amount
        );
        IRewardTracker(feePosiTracker).stakeForAccount(
            _account,
            _account,
            bonusPosiTracker,
            _amount
        );

        emit StakePosi(_account, _token, _amount);
    }

    function _unstakePosi(
        address _account,
        address _token,
        uint256 _amount,
        bool _shouldReduceBnPosi
    ) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        uint256 balance = IRewardTracker(stakedPosiTracker).stakedAmounts(
            _account
        );

        IRewardTracker(feePosiTracker).unstakeForAccount(
            _account,
            bonusPosiTracker,
            _amount,
            _account
        );
        IRewardTracker(bonusPosiTracker).unstakeForAccount(
            _account,
            stakedPosiTracker,
            _amount,
            _account
        );
        IRewardTracker(stakedPosiTracker).unstakeForAccount(
            _account,
            _token,
            _amount,
            _account
        );

        if (_shouldReduceBnPosi) {
            uint256 bnPosiAmount = IRewardTracker(bonusPosiTracker)
                .claimForAccount(_account, _account);
            if (bnPosiAmount > 0) {
                IRewardTracker(feePosiTracker).stakeForAccount(
                    _account,
                    _account,
                    bnPosi,
                    bnPosiAmount
                );
            }

            uint256 stakedBnPosi = IRewardTracker(feePosiTracker)
                .depositBalances(_account, bnPosi);
            if (stakedBnPosi > 0) {
                uint256 reductionAmount = stakedBnPosi.mul(_amount).div(
                    balance
                );
                IRewardTracker(feePosiTracker).unstakeForAccount(
                    _account,
                    bnPosi,
                    reductionAmount,
                    _account
                );
                IMintable(bnPosi).burn(_account, reductionAmount);
            }
        }

        emit UnstakePosi(_account, _token, _amount);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;

}
