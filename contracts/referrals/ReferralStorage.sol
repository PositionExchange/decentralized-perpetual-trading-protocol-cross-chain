// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "./interfaces/IReferralStorage.sol";

contract ReferralStorage is
    IReferralStorage,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeMath for uint256;

    struct Tier {
        uint256 totalRebate; // e.g. 2400 for 24%
        uint256 discountShare; // 5000 for 50%/50%, 7000 for 30% rebates/70% discount
    }

    uint256 public constant BASIS_POINTS = 10000;

    mapping(uint256 => Tier) public tiers;
    mapping(address => bool) public isAdmin;

    mapping(bytes32 => address) public override codes; // map code vs trader address
    mapping(address => bytes32) public override traderCodes; // map trader address vs code
    mapping(address => bytes32) public override traderReferralCodes; // link between user <> their referrer code
    mapping(address => uint256) public override referrerTiers; // link between user <> tier

    event SetAdmin(address admin, bool isActive);
    event SetTier(uint256 tierId, uint256 totalRebate, uint256 discountShare);
    event RegisterCode(address account, bytes32 code);
    event SetReferrerTier(address referrer, uint256 tierId);
    event SetTraderReferralCode(address account, bytes32 code);


    modifier onlyAdmin() {
        require(isAdmin[msg.sender], "ReferralStorage: forbidden");
        _;
    }

    function initialize() public initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
    }

    function setAdmin(address _admin, bool _isActive) external onlyOwner {
        isAdmin[_admin] = _isActive;
        emit SetAdmin(_admin, _isActive);
    }

    function setTier(
        uint256 _tierId,
        uint256 _totalRebate,
        uint256 _discountShare
    ) external override onlyOwner {
        require(
            _totalRebate <= BASIS_POINTS,
            "ReferralStorage: invalid totalRebate"
        );
        require(
            _discountShare <= BASIS_POINTS,
            "ReferralStorage: invalid discountShare"
        );

        Tier memory tier = tiers[_tierId];
        tier.totalRebate = _totalRebate;
        tier.discountShare = _discountShare;
        tiers[_tierId] = tier;
        emit SetTier(_tierId, _totalRebate, _discountShare);
    }

    function setReferrerTier(
        address _referrer,
        uint256 _tierId
    ) external onlyAdmin {
        referrerTiers[_referrer] = _tierId;
        emit SetReferrerTier(_referrer, _tierId);
    }

    function registerCode(bytes32 _code) external {
        require(_code != bytes32(0), "ReferralStorage: invalid code");
        require(
            traderCodes[msg.sender] == bytes32(0),
            "ReferralStorage: trader already has code"
        );
        require(
            codes[_code] == address(0),
            "ReferralStorage: code already exists"
        );

        codes[_code] = msg.sender;
        traderCodes[msg.sender] = _code;
        referrerTiers[msg.sender] = 1;
        emit RegisterCode(msg.sender, _code);
    }

    function setTraderReferralCode(bytes32 _code) external {
        require(traderReferralCodes[msg.sender] == bytes32(0), "ReferralStorage: trader referral code already set");
        address referrer = codes[_code];
        require(referrer != address(0), "ReferralStorage: referrer not exists");
        require(referrer != msg.sender, "ReferralStorage: self referred");
        require(
            referrerTiers[msg.sender] <= referrerTiers[referrer],
            "ReferralStorage: must less than referrer tier"
        );
        require(
            traderReferralCodes[referrer] != traderCodes[msg.sender],
            "ReferralStorage: cannot refer user referrer"
        );
        traderReferralCodes[msg.sender] = _code;
        emit SetTraderReferralCode(msg.sender, _code);
    }
}
