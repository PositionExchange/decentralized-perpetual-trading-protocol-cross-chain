// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./interfaces/ITimelockTarget.sol";
import "./interfaces/ITimelock.sol";
import "./interfaces/IHandlerTarget.sol";
import "../access/interfaces/IAdmin.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IVaultUtils.sol";
import "../interfaces/ILpManager.sol";
import "../referrals/interfaces/IReferralStorage.sol";
import "../token/interface/IYieldToken.sol";
import "../token/interface/IBaseToken.sol";
import "../token/interface/IMintable.sol";
import "../token/interface/IUSDP.sol";
import "../staking/interfaces/IVester.sol";
import "../staking/interfaces/IRewardRouter.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Timelock is OwnableUpgradeable, ITimelock {
    using SafeMath for uint256;

    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant MAX_BUFFER = 5 days;
    uint256 public constant MAX_FUNDING_RATE_FACTOR = 200; // 0.02%
    uint256 public constant MAX_LEVERAGE_VALIDATION = 500000; // 50x

    uint256 public buffer;
    address public admin;

    address public tokenManager;
    address public mintReceiver;
    address public glpManager;
    address public rewardRouter;
    uint256 public maxTokenSupply;

    uint256 public override marginFeeBasisPoints;
    uint256 public maxMarginFeeBasisPoints;
    bool public shouldToggleIsLeverageEnabled;

    mapping(bytes32 => uint256) public pendingActions;

    mapping(address => bool) public isHandler;
    mapping(address => bool) public isKeeper;

    event SignalPendingAction(bytes32 action);
    event SignalApprove(
        address token,
        address spender,
        uint256 amount,
        bytes32 action
    );
    event SignalWithdrawToken(
        address target,
        address token,
        address receiver,
        uint256 amount,
        bytes32 action
    );
    event SignalMint(
        address token,
        address receiver,
        uint256 amount,
        bytes32 action
    );
    event SignalSetGov(address target, address gov, bytes32 action);
    event SignalSetHandler(
        address target,
        address handler,
        bool isActive,
        bytes32 action
    );
    event SignalSetPriceFeed(address vault, address priceFeed, bytes32 action);
    event SignalRedeemUsdg(address vault, address token, uint256 amount);
    event SignalVaultSetTokenConfig(
        address vault,
        address token,
        uint256 tokenDecimals,
        uint256 tokenWeight,
        uint256 minProfitBps,
        uint256 maxUsdgAmount,
        bool isStable,
        bool isShortable
    );
    event ClearAction(bytes32 action);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Timelock: forbidden");
        _;
    }

    modifier onlyHandlerAndAbove() {
        require(
            msg.sender == admin || isHandler[msg.sender],
            "Timelock: forbidden"
        );
        _;
    }

    modifier onlyKeeperAndAbove() {
        require(
            msg.sender == admin ||
                isHandler[msg.sender] ||
                isKeeper[msg.sender],
            "Timelock: forbidden"
        );
        _;
    }

    modifier onlyTokenManager() {
        require(msg.sender == tokenManager, "Timelock: forbidden");
        _;
    }

    function initialize(
        address _admin,
        uint256 _buffer,
        address _tokenManager,
        address _mintReceiver,
        address _glpManager,
        address _rewardRouter,
        uint256 _maxTokenSupply,
        uint256 _marginFeeBasisPoints,
        uint256 _maxMarginFeeBasisPoints
    ) public initializer {
        __Ownable_init();
        require(_buffer <= MAX_BUFFER, "Timelock: invalid _buffer");
        admin = _admin;
        buffer = _buffer;
        tokenManager = msg.sender;
        mintReceiver = _mintReceiver;
        glpManager = _glpManager;
        rewardRouter = _rewardRouter;
        maxTokenSupply = _maxTokenSupply;

        marginFeeBasisPoints = _marginFeeBasisPoints;
        maxMarginFeeBasisPoints = _maxMarginFeeBasisPoints;
    }

    function setAdmin(address _admin) external override onlyOwner {
        admin = _admin;
    }

    function setExternalAdmin(
        address _target,
        address _admin
    ) external onlyAdmin {
        require(_target != address(this), "Timelock: invalid _target");
        IAdmin(_target).setAdmin(_admin);
    }

    function setContractHandler(
        address _handler,
        bool _isActive
    ) external onlyAdmin {
        isHandler[_handler] = _isActive;
    }

    function initGlpManager() external onlyAdmin {
        ILpManager _glpManager = ILpManager(glpManager);

        IMintable glp = IMintable(_glpManager.plpToken());
        glp.setMinter(glpManager, true);

        IUSDP usdp = IUSDP(_glpManager.usdp());
        usdp.addVault(glpManager);

        IVault vault = _glpManager.vault();
        vault.setWhitelistCaller(glpManager, true);
    }

    function initRewardRouter() external onlyAdmin {
        IRewardRouter _rewardRouter = IRewardRouter(rewardRouter);

        IHandlerTarget(_rewardRouter.feePlpTracker()).setHandler(
            rewardRouter,
            true
        );
        IHandlerTarget(_rewardRouter.stakedPlpTracker()).setHandler(
            rewardRouter,
            true
        );
        IHandlerTarget(glpManager).setHandler(rewardRouter, true);
    }

    function setKeeper(address _keeper, bool _isActive) external onlyAdmin {
        isKeeper[_keeper] = _isActive;
    }

    function setBuffer(uint256 _buffer) external onlyAdmin {
        require(_buffer <= MAX_BUFFER, "Timelock: invalid _buffer");
        require(_buffer > buffer, "Timelock: buffer cannot be decreased");
        buffer = _buffer;
    }

    function setMaxLeverage(
        address _vault,
        uint256 _maxLeverage
    ) external onlyAdmin {
        require(
            _maxLeverage > MAX_LEVERAGE_VALIDATION,
            "Timelock: invalid _maxLeverage"
        );
        /* IVault(_vault).setMaxLeverage(_maxLeverage); */
        // TODO: implement
        revert("Timelock: not implemented");
    }

    function setFundingRate(
        address _vault,
        uint256 _fundingInterval,
        uint256 _fundingRateFactor,
        uint256 _stableFundingRateFactor
    ) external onlyKeeperAndAbove {
        require(
            _fundingRateFactor < MAX_FUNDING_RATE_FACTOR,
            "Timelock: invalid _fundingRateFactor"
        );
        require(
            _stableFundingRateFactor < MAX_FUNDING_RATE_FACTOR,
            "Timelock: invalid _stableFundingRateFactor"
        );
        // TODO: implement
        revert("Timelock: not implemented");
        /* IVault(_vault).setFundingRate(_fundingInterval, _fundingRateFactor, _stableFundingRateFactor); */
    }

    function setShouldToggleIsLeverageEnabled(
        bool _shouldToggleIsLeverageEnabled
    ) external onlyHandlerAndAbove {
        shouldToggleIsLeverageEnabled = _shouldToggleIsLeverageEnabled;
    }

    function setMarginFeeBasisPoints(
        uint256 _marginFeeBasisPoints,
        uint256 _maxMarginFeeBasisPoints
    ) external onlyHandlerAndAbove {
        marginFeeBasisPoints = _marginFeeBasisPoints;
        maxMarginFeeBasisPoints = _maxMarginFeeBasisPoints;
    }

    function setSwapFees(
        address _vault,
        uint256 _taxBasisPoints,
        uint256 _stableTaxBasisPoints,
        uint256 _mintBurnFeeBasisPoints,
        uint256 _swapFeeBasisPoints,
        uint256 _stableSwapFeeBasisPoints
    ) external onlyKeeperAndAbove {
        IVault vault = IVault(_vault);

        vault.setFees(
            _taxBasisPoints,
            _stableTaxBasisPoints,
            _mintBurnFeeBasisPoints,
            _swapFeeBasisPoints,
            _stableSwapFeeBasisPoints,
            maxMarginFeeBasisPoints,
            vault.minProfitTime(),
            vault.hasDynamicFees()
        );
    }

    // assign _marginFeeBasisPoints to this.marginFeeBasisPoints
    // because enableLeverage would update Vault.marginFeeBasisPoints to this.marginFeeBasisPoints
    // and disableLeverage would reset the Vault.marginFeeBasisPoints to this.maxMarginFeeBasisPoints
    function setFees(
        address _vault,
        uint256 _taxBasisPoints,
        uint256 _stableTaxBasisPoints,
        uint256 _mintBurnFeeBasisPoints,
        uint256 _swapFeeBasisPoints,
        uint256 _stableSwapFeeBasisPoints,
        uint256 _marginFeeBasisPoints,
        uint256 _minProfitTime,
        bool _hasDynamicFees
    ) external onlyKeeperAndAbove {
        marginFeeBasisPoints = _marginFeeBasisPoints;

        IVault(_vault).setFees(
            _taxBasisPoints,
            _stableTaxBasisPoints,
            _mintBurnFeeBasisPoints,
            _swapFeeBasisPoints,
            _stableSwapFeeBasisPoints,
            maxMarginFeeBasisPoints,
            _minProfitTime,
            _hasDynamicFees
        );
    }

    function enableLeverage(
        address _vault
    ) external override onlyHandlerAndAbove {
        IVault vault = IVault(_vault);

        if (shouldToggleIsLeverageEnabled) {
            // TODO: implement
            revert("Timelock: not implemented");
            /* vault.setIsLeverageEnabled(true); */
        }

        vault.setFees(
            vault.taxBasisPoints(),
            vault.stableTaxBasisPoints(),
            vault.mintBurnFeeBasisPoints(),
            vault.swapFeeBasisPoints(),
            vault.stableSwapFeeBasisPoints(),
            marginFeeBasisPoints,
            vault.minProfitTime(),
            vault.hasDynamicFees()
        );
    }

    function disableLeverage(
        address _vault
    ) external override onlyHandlerAndAbove {
        IVault vault = IVault(_vault);

        if (shouldToggleIsLeverageEnabled) {
            // TODO: implement
            revert("Timelock: not implemented");
            /* vault.setIsLeverageEnabled(false); */
        }

        vault.setFees(
            vault.taxBasisPoints(),
            vault.stableTaxBasisPoints(),
            vault.mintBurnFeeBasisPoints(),
            vault.swapFeeBasisPoints(),
            vault.stableSwapFeeBasisPoints(),
            maxMarginFeeBasisPoints, // marginFeeBasisPoints
            vault.minProfitTime(),
            vault.hasDynamicFees()
        );
    }

    function setIsLeverageEnabled(
        address _vault,
        bool _isLeverageEnabled
    ) external override onlyHandlerAndAbove {
        // TODO: implement
        revert("Timelock: not implemented");
        /* IVault(_vault).setIsLeverageEnabled(_isLeverageEnabled); */
    }

    function setTokenConfig(
        address _vault,
        address _token,
        uint128 _tokenWeight,
        uint64 _minProfitBps,
        uint128 _maxUsdgAmount,
        uint256 _bufferAmount,
        uint256 _usdgAmount
    ) external onlyKeeperAndAbove {
        require(_minProfitBps <= 500, "Timelock: invalid _minProfitBps");

        IVault vault = IVault(_vault);
        require(
            vault.isWhitelistedTokens(_token),
            "Timelock: token not yet whitelisted"
        );

        uint256 tokenDecimals = vault.tokenDecimals(_token);
        bool isStable = vault.stableTokens(_token);
        bool isShortable = vault.shortableTokens(_token);

        IVault(_vault).setConfigToken(
            _token,
            uint8(tokenDecimals),
            _minProfitBps,
            _tokenWeight,
            _maxUsdgAmount,
            isStable,
            isShortable
        );

        IVault(_vault).setBufferAmount(_token, _bufferAmount);

        IVault(_vault).setUsdgAmount(_token, _usdgAmount);
    }

    function setUsdgAmounts(
        address _vault,
        address[] memory _tokens,
        uint256[] memory _usdgAmounts
    ) external onlyKeeperAndAbove {
        for (uint256 i = 0; i < _tokens.length; i++) {
            IVault(_vault).setUsdgAmount(_tokens[i], _usdgAmounts[i]);
        }
    }

    function updateUsdgSupply(uint256 usdgAmount) external onlyKeeperAndAbove {
        address usdp = ILpManager(glpManager).usdp();
        uint256 balance = IERC20(usdp).balanceOf(glpManager);

        IUSDP(usdp).addVault(address(this));

        if (usdgAmount > balance) {
            uint256 mintAmount = usdgAmount.sub(balance);
            IUSDP(usdp).mint(glpManager, mintAmount);
        } else {
            uint256 burnAmount = balance.sub(usdgAmount);
            IUSDP(usdp).burn(glpManager, burnAmount);
        }

        IUSDP(usdp).removeVault(address(this));
    }

    function setShortsTrackerAveragePriceWeight(
        uint256 _shortsTrackerAveragePriceWeight
    ) external onlyAdmin {
        ILpManager(glpManager).setShortsTrackerAveragePriceWeight(
            _shortsTrackerAveragePriceWeight
        );
    }

    function setGlpCooldownDuration(
        uint256 _cooldownDuration
    ) external onlyAdmin {
        require(
            _cooldownDuration < 2 hours,
            "Timelock: invalid _cooldownDuration"
        );
        ILpManager(glpManager).setCooldownDuration(_cooldownDuration);
    }

    function setMaxGlobalShortSize(
        address _vault,
        address _token,
        uint256 _amount
    ) external onlyAdmin {
        // TODO: implement
        revert("Timelock: not implemented");

        /* IVault(_vault).setMaxGlobalShortSize(_token, _amount); */
    }

    function removeAdmin(address _token, address _account) external onlyAdmin {
        IYieldToken(_token).removeAdmin(_account);
    }

    function setIsSwapEnabled(
        address _vault,
        bool _isSwapEnabled
    ) external onlyKeeperAndAbove {
        IVault(_vault).setIsSwapEnabled(_isSwapEnabled);
    }

    function setTier(
        address _referralStorage,
        uint256 _tierId,
        uint256 _totalRebate,
        uint256 _discountShare
    ) external onlyKeeperAndAbove {
        IReferralStorage(_referralStorage).setTier(
            _tierId,
            _totalRebate,
            _discountShare
        );
    }

    function setVaultUtils(
        address _vault,
        IVaultUtils _vaultUtils
    ) external onlyAdmin {
        IVault(_vault).setVaultUtils(_vaultUtils);
    }

    function setMaxGasPrice(
        address _vault,
        uint256 _maxGasPrice
    ) external onlyAdmin {
        require(_maxGasPrice > 5000000000, "Invalid _maxGasPrice");
        IVault(_vault).setMaxGasPrice(_maxGasPrice);
    }

    function withdrawFees(
        address _vault,
        address _token,
        address _receiver
    ) external onlyAdmin {
        IVault(_vault).withdrawFees(_token, _receiver);
    }

    function batchWithdrawFees(
        address _vault,
        address[] memory _tokens
    ) external onlyKeeperAndAbove {
        for (uint256 i = 0; i < _tokens.length; i++) {
            IVault(_vault).withdrawFees(_tokens[i], admin);
        }
    }

    function setInPrivateTransferMode(
        address _token,
        bool _inPrivateTransferMode
    ) external onlyAdmin {
        IBaseToken(_token).setInPrivateTransferMode(_inPrivateTransferMode);
    }

    function batchSetBonusRewards(
        address _vester,
        address[] memory _accounts,
        uint256[] memory _amounts
    ) external onlyKeeperAndAbove {
        require(
            _accounts.length == _amounts.length,
            "Timelock: invalid lengths"
        );

        IHandlerTarget(_vester).setHandler(address(this), true);

        for (uint256 i = 0; i < _accounts.length; i++) {
            address account = _accounts[i];
            uint256 amount = _amounts[i];
            IVester(_vester).setBonusRewards(account, amount);
        }

        IHandlerTarget(_vester).setHandler(address(this), false);
    }

    function transferIn(
        address _sender,
        address _token,
        uint256 _amount
    ) external onlyAdmin {
        IERC20(_token).transferFrom(_sender, address(this), _amount);
    }

    function signalApprove(
        address _token,
        address _spender,
        uint256 _amount
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked("approve", _token, _spender, _amount)
        );
        _setPendingAction(action);
        emit SignalApprove(_token, _spender, _amount, action);
    }

    function approve(
        address _token,
        address _spender,
        uint256 _amount
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked("approve", _token, _spender, _amount)
        );
        _validateAction(action);
        _clearAction(action);
        IERC20(_token).approve(_spender, _amount);
    }

    function signalWithdrawToken(
        address _target,
        address _token,
        address _receiver,
        uint256 _amount
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked(
                "withdrawToken",
                _target,
                _token,
                _receiver,
                _amount
            )
        );
        _setPendingAction(action);
        emit SignalWithdrawToken(_target, _token, _receiver, _amount, action);
    }

    function withdrawToken(
        address _target,
        address _token,
        address _receiver,
        uint256 _amount
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked(
                "withdrawToken",
                _target,
                _token,
                _receiver,
                _amount
            )
        );
        _validateAction(action);
        _clearAction(action);
        IBaseToken(_target).withdrawToken(_token, _receiver, _amount);
    }

    function signalMint(
        address _token,
        address _receiver,
        uint256 _amount
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked("mint", _token, _receiver, _amount)
        );
        _setPendingAction(action);
        emit SignalMint(_token, _receiver, _amount, action);
    }

    function processMint(
        address _token,
        address _receiver,
        uint256 _amount
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked("mint", _token, _receiver, _amount)
        );
        _validateAction(action);
        _clearAction(action);

        _mint(_token, _receiver, _amount);
    }

    function signalSetGov(
        address _target,
        address _gov
    ) external override onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("setGov", _target, _gov));
        _setPendingAction(action);
        emit SignalSetGov(_target, _gov, action);
    }

    function setGov(address _target, address _gov) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("setGov", _target, _gov));
        _validateAction(action);
        _clearAction(action);
        ITimelockTarget(_target).setGov(_gov);
    }

    function signalSetHandler(
        address _target,
        address _handler,
        bool _isActive
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked("setHandler", _target, _handler, _isActive)
        );
        _setPendingAction(action);
        emit SignalSetHandler(_target, _handler, _isActive, action);
    }

    function setHandler(
        address _target,
        address _handler,
        bool _isActive
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked("setHandler", _target, _handler, _isActive)
        );
        _validateAction(action);
        _clearAction(action);
        IHandlerTarget(_target).setHandler(_handler, _isActive);
    }

    function signalSetPriceFeed(
        address _vault,
        address _priceFeed
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked("setPriceFeed", _vault, _priceFeed)
        );
        _setPendingAction(action);
        emit SignalSetPriceFeed(_vault, _priceFeed, action);
    }

    function setPriceFeed(
        address _vault,
        address _priceFeed
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked("setPriceFeed", _vault, _priceFeed)
        );
        _validateAction(action);
        _clearAction(action);
        IVault(_vault).setPriceFeed(_priceFeed);
    }

    function signalRedeemUsdg(
        address _vault,
        address _token,
        uint256 _amount
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked("redeemUsdg", _vault, _token, _amount)
        );
        _setPendingAction(action);
        emit SignalRedeemUsdg(_vault, _token, _amount);
    }

    function redeemUsdg(
        address _vault,
        address _token,
        uint256 _amount
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked("redeemUsdg", _vault, _token, _amount)
        );
        _validateAction(action);
        _clearAction(action);

        address usdp = IVault(_vault).usdp();
        IVault(_vault).setWhitelistCaller(address(this), true);
        IUSDP(usdp).addVault(address(this));

        IUSDP(usdp).mint(address(this), _amount);
        IERC20(usdp).transfer(address(_vault), _amount);

        IVault(_vault).sellUSDP(_token, mintReceiver);

        IVault(_vault).setWhitelistCaller(address(this), false);
        IUSDP(usdp).removeVault(address(this));
    }

    function signalVaultSetTokenConfig(
        address _vault,
        address _token,
        uint256 _tokenDecimals,
        uint256 _tokenWeight,
        uint256 _minProfitBps,
        uint256 _maxUsdgAmount,
        bool _isStable,
        bool _isShortable
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked(
                "vaultSetTokenConfig",
                _vault,
                _token,
                _tokenDecimals,
                _tokenWeight,
                _minProfitBps,
                _maxUsdgAmount,
                _isStable,
                _isShortable
            )
        );

        _setPendingAction(action);

        emit SignalVaultSetTokenConfig(
            _vault,
            _token,
            _tokenDecimals,
            _tokenWeight,
            _minProfitBps,
            _maxUsdgAmount,
            _isStable,
            _isShortable
        );
    }

    function vaultSetTokenConfig(
        address _vault,
        address _token,
        uint8 _tokenDecimals,
        uint128 _tokenWeight,
        uint64 _minProfitBps,
        uint128 _maxUsdgAmount,
        bool _isStable,
        bool _isShortable
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked(
                "vaultSetTokenConfig",
                _vault,
                _token,
                _tokenDecimals,
                _tokenWeight,
                _minProfitBps,
                _maxUsdgAmount,
                _isStable,
                _isShortable
            )
        );

        _validateAction(action);
        _clearAction(action);

        IVault(_vault).setConfigToken(
            _token,
            _tokenDecimals,
            _minProfitBps,
            _tokenWeight,
            _maxUsdgAmount,
            _isStable,
            _isShortable
        );
    }

    function cancelAction(bytes32 _action) external onlyAdmin {
        _clearAction(_action);
    }

    function _mint(address _token, address _receiver, uint256 _amount) private {
        IMintable mintable = IMintable(_token);

        mintable.setMinter(address(this), true);

        mintable.mint(_receiver, _amount);
        require(
            IERC20(_token).totalSupply() <= maxTokenSupply,
            "Timelock: maxTokenSupply exceeded"
        );

        mintable.setMinter(address(this), false);
    }

    function _setPendingAction(bytes32 _action) private {
        require(
            pendingActions[_action] == 0,
            "Timelock: action already signalled"
        );
        pendingActions[_action] = block.timestamp.add(buffer);
        emit SignalPendingAction(_action);
    }

    function _validateAction(bytes32 _action) private view {
        require(pendingActions[_action] != 0, "Timelock: action not signalled");
        require(
            pendingActions[_action] < block.timestamp,
            "Timelock: action time not yet passed"
        );
    }

    function _clearAction(bytes32 _action) private {
        require(pendingActions[_action] != 0, "Timelock: invalid _action");
        delete pendingActions[_action];
        emit ClearAction(_action);
    }
}
