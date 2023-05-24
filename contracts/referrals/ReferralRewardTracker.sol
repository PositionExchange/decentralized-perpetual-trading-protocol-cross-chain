// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./interfaces/IReferralStorage.sol";
import "./interfaces/IReferralRewardTracker.sol";

contract ReferralRewardTracker is
    IReferralRewardTracker,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    uint256 public constant BASIS_POINTS = 10000;

    address public rewardToken;
    address public referralStorage;
    uint256 public positionValidationInterval;
    uint256 public positionValidationNotional;

    mapping(address => bool) public isCounterParty;
    mapping(address => uint256) public claimableCommission;
    mapping(address => uint256) public claimableDiscount;
    mapping(address => mapping(address => uint256)) public positionTimestamp;

    event SetRewardToken(address rewardToken, uint256 tokenDecimal);
    event SetCounterParty(address counterParty, bool isActive);
    event ClaimCommission(address receiver, uint256 amount);
    event ClaimDiscount(address receiver, uint256 amount);
    event UpdateClaimableCommissionReward(address referrer, address trader, uint256 amount, uint256 timestamp);
    event UpdateClaimableDiscountReward(address trader, uint256 amount);

    modifier onlyCounterParty() {
        require(isCounterParty[msg.sender],"ReferralStorage: onlyCounterParty");
        _;
    }

    function initialize(
        address _rewardToken,
        uint256 _tokenDecimal,
        address _referralStorage
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
        rewardToken = _rewardToken;
        tokenDecimal = _tokenDecimal;
        referralStorage = _referralStorage;
        positionValidationInterval = 1800;
        positionValidationNotional = 50*WEI_DECIMALS;
    }

    function setRewardToken(address _address, uint256 _tokenDecimal) external onlyOwner {
        rewardToken = _address;
        tokenDecimal = _tokenDecimal;
        emit SetRewardToken(_address,_tokenDecimal);
    }

    function setCounterParty(address _address, bool _isActive) external onlyOwner {
        isCounterParty[_address] = _isActive;
        emit SetCounterParty(_address, _isActive);
    }

    function setPositionValidationInterval(uint256 _interval) external onlyOwner {
        positionValidationInterval = _interval;
    }

    function setPositionValidationNotional(uint256 _notional) external onlyOwner {
        positionValidationNotional = _notional;
    }

    function claimCommission() external nonReentrant {
        uint256 tokenAmount = claimableCommission[msg.sender];
        claimableCommission[msg.sender] = 0;

        if (tokenAmount > 0) {
            IERC20(rewardToken).safeTransfer(msg.sender, tokenAmount.mul(10**tokenDecimal).div(WEI_DECIMALS));
            emit ClaimCommission(msg.sender, tokenAmount);
        }
    }

    function claimDiscount() external nonReentrant {
        uint256 tokenAmount = claimableDiscount[msg.sender];
        claimableDiscount[msg.sender] = 0;

        if (tokenAmount > 0) {
            IERC20(rewardToken).safeTransfer(msg.sender, tokenAmount.mul(10**tokenDecimal).div(WEI_DECIMALS));
            emit ClaimDiscount(msg.sender, tokenAmount);
        }
    }

    function updateClaimableReward(
        address _trader,
        uint256 _fee
    ) external nonReentrant onlyCounterParty {
        bool isActive = IReferralStorage(referralStorage).traderStatus(_trader);
        if (!isActive) {
            return;
        }

        (address referrer, uint256 rebate, uint256 discount) =
            IReferralStorage(referralStorage).getReferrerInfo(_trader);

        if (referrer == address(0)) {
            return;
        }

        uint256 commissionAmount = _fee.mul(rebate).div(BASIS_POINTS);
        claimableCommission[referrer] = claimableCommission[referrer].add(commissionAmount);

        uint256 discountAmount = _fee.mul(discount).div(BASIS_POINTS);
        claimableDiscount[_trader] = claimableDiscount[_trader].add(discountAmount);

        emit UpdateClaimableCommissionReward(referrer, _trader, commissionAmount, block.timestamp);
        emit UpdateClaimableDiscountReward(_trader, discountAmount);
    }

    function updateRefereeStatus(
        address _trader,
        address _indexToken,
        uint256 _timestamp,
        uint256 _notional,
        bool _isIncrease
    ) external nonReentrant onlyCounterParty {
        bool isStatusUpgradeable = IReferralStorage(referralStorage).isStatusUpgradeable(_trader);
        if (isStatusUpgradeable) {
            return;
        }

        uint256 createTimestamp = positionTimestamp[_trader][_indexToken];
        if (createTimestamp == 0) {
            if (_isIncrease && _notional < positionValidationNotional) {
                return;
            }
            positionTimestamp[_trader][_indexToken] = _timestamp;
            return;
        }

        if (_isIncrease){
            return;
        }

        delete positionTimestamp[_trader][_indexToken];
        if (_timestamp.sub(createTimestamp)  > positionValidationInterval) {
            IReferralStorage(referralStorage).setTraderStatus(_trader,true);
        }
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
    */
    uint256[49] private __gap;
    uint256 public tokenDecimal;
    uint256 public constant WEI_DECIMALS = 10**18;
}
