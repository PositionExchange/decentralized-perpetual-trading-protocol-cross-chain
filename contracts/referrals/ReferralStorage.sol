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
    mapping(address => bool) public isCounterParty;

    mapping(bytes32 => address) public override codes; // map code vs trader address
    mapping(address => bytes32) public override traderCodes; // map trader address vs code
    mapping(address => bytes32) public override traderReferralCodes; // link between user <> their referrer code
    mapping(address => uint256) public override referrerTiers; // link between user <> tier
    mapping(address => bool) public override traderStatus; // true => active, false => pending

    event SetAdmin(address admin, bool isActive);
    event SetCounterParty(address counterParty, bool isActive);
    event SetTier(uint256 tierId, uint256 totalRebate, uint256 discountShare);
    event RegisterCode(address account, bytes32 code, uint256 timestamp);
    event SetReferrerTier(address referrer, uint256 tierId, uint256 timestamp);
    event SetTraderReferralCode(address account, bytes32 code);
    event SetTraderStatus(address trader, bool isActive, uint256 timestamp);

    modifier onlyAdmin() {
        require(isAdmin[msg.sender], "ReferralStorage: onlyAdmin");
        _;
    }

    modifier onlyCounterParty() {
        require(isCounterParty[msg.sender],"ReferralStorage: onlyCounterParty");
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

    function setCounterParty(address _address, bool _isActive) external onlyOwner {
        isCounterParty[_address] = _isActive;
        emit SetCounterParty(_address, _isActive);
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
        emit SetReferrerTier(_referrer, _tierId, block.timestamp);
    }

    function setTraderStatus(
        address _trader,
        bool _isActive
    ) external onlyCounterParty {
        traderStatus[_trader] = _isActive;
        emit SetTraderStatus(_trader, _isActive, block.timestamp);
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
        emit RegisterCode(msg.sender, _code, block.timestamp);
    }

    function setTraderReferralCode(bytes32 _code) external {
        _validateSetReferralRequest(msg.sender, _code);
        traderReferralCodes[msg.sender] = _code;
        traderStatus[msg.sender] = false;
        emit SetTraderReferralCode(msg.sender, _code);
    }

    function getReferrerInfo(
        address _trader
    ) external view returns (address , uint256, uint256){
        address referrer = codes[traderReferralCodes[_trader]];
        Tier memory tier = tiers[referrerTiers[referrer]];
        return (referrer, tier.totalRebate, tier.discountShare);
    }

    function isStatusUpgradeable(address _trader) external view returns (bool) {
        if (traderReferralCodes[_trader] == bytes32(0)) return false;
        return traderStatus[_trader];
    }

    function _validateSetReferralRequest(
        address _trader,
        bytes32 _code
    ) internal {
        require(
            traderReferralCodes[_trader] == bytes32(0),
            "ReferralStorage: trader referral code already set"
        );
        address referrer = codes[_code];
        require(referrer != address(0), "ReferralStorage: referrer not exists");
        require(referrer != _trader, "ReferralStorage: self referred");
        require(
            referrerTiers[_trader] <= referrerTiers[referrer],
            "ReferralStorage: must less than referrer tier"
        );
        if (traderReferralCodes[referrer] != bytes32(0)){
            require(
                traderReferralCodes[referrer] != traderCodes[_trader],
                "ReferralStorage: cannot refer user referrer"
            );
        }
    }
}

