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

    mapping(address => bool) isCounterParty;
    mapping(address => uint256) public claimableCommission;
    mapping(address => uint256) public claimableDiscount;
    mapping(address => mapping(address => uint256)) public positionTimestamp;

    event SetRewardToken(address rewardToken);
    event SetCounterParty(address counterParty, bool isActive);
    event ClaimCommission(address receiver, uint256 amount);
    event ClaimDiscount(address receiver, uint256 amount);
    event UpdateClaimableCommissionReward(address referrer, address _trader, uint256 amount);
    event UpdateClaimableDiscountReward(address _trader, uint256 amount);

    modifier onlyCounterParty() {
        require(isCounterParty[msg.sender],"ReferralStorage: onlyCounterParty");
        _;
    }

    function initialize(
        address _rewardToken,
        address _referralStorage
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
        rewardToken = _rewardToken;
        referralStorage = _referralStorage;
        positionValidationInterval = 1800;
    }

    function setRewardToken(address _address) external onlyOwner {
        rewardToken = _address;
        emit SetRewardToken(_address);
    }

    function setCounterParty(address _address, bool _isActive) external onlyOwner {
        isCounterParty[_address] = _isActive;
        emit SetCounterParty(_address, _isActive);
    }

    function setPositionValidationInterval(uint256 _interval) external onlyOwner {
        positionValidationInterval = _interval;
    }

    function claimCommission() external nonReentrant {
        uint256 tokenAmount = claimableCommission[msg.sender];
        claimableCommission[msg.sender] = 0;

        if (tokenAmount > 0) {
            IERC20(rewardToken).safeTransfer(msg.sender, tokenAmount);
            emit ClaimCommission(msg.sender, tokenAmount);
        }
    }

    function claimDiscount() external nonReentrant {
        uint256 tokenAmount = claimableDiscount[msg.sender];
        claimableDiscount[msg.sender] = 0;

        if (tokenAmount > 0) {
            IERC20(rewardToken).safeTransfer(msg.sender, tokenAmount);
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

        uint256 commissionAmount = _fee.mul(rebate).div(BASIS_POINTS);
        claimableCommission[referrer] = claimableCommission[referrer].add(commissionAmount);

        uint256 discountAmount = _fee.mul(discount).div(BASIS_POINTS);
        claimableDiscount[_trader] = claimableDiscount[_trader].add(discountAmount);

        emit UpdateClaimableCommissionReward(referrer, _trader, commissionAmount);
        emit UpdateClaimableDiscountReward(_trader, discountAmount);
    }

    function updateRefereeStatus(
        address _trader,
        address _indexToken,
        uint256 _timestamp,
        bool _isIncrease
    ) external nonReentrant onlyCounterParty {
        bool isActive = IReferralStorage(referralStorage).traderStatus(_trader);
        if (isActive) {
            return;
        }

        uint256 createTimestamp = positionTimestamp[_trader][_indexToken];
        if (createTimestamp == 0) {
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
}
