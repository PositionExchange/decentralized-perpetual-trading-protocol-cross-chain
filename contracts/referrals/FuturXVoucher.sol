/**
 * @author Musket
 */
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../interfaces/IFuturXVoucher.sol";

contract FuturXVoucher is ERC721EnumerableUpgradeable, OwnableUpgradeable {
    struct Voucher {
        uint256 id;
        address owner;
        uint256 value;
        uint256 expiredTime;
        uint256 maxDiscountValue;
        uint8 voucherType;
        bool isActive;
    }

    address public futurXGateway;

    mapping(uint256 => Voucher) public voucherInfo;
    mapping(address => bool) public miner;

    uint256 public globalVoucherId;
    uint256 public defaultExpireTime;
    mapping(uint8 => uint256) public expireTimeMap;

    mapping(address => uint256) public voucherValuePerAccount;
    uint256 public maxVoucherValuePerAccount;

    event VoucherDistributed(
        address owner,
        uint256 value,
        uint256 maxDiscountValue,
        uint8 voucherType,
        uint256 voucherId
    );

    event VoucherClaim(address owner, uint256 voucherId, uint256 expiredTime);

    event VoucherBurned(address owner, uint256 voucherId);

    modifier onlyMiner() {
        require(miner[msg.sender], "Only miner");
        _;
    }

    function initialize(address _futurXGateway) public initializer {
        __Ownable_init();
        __ERC721_init("FuturX Voucher", "FV");
        futurXGateway = _futurXGateway;

        globalVoucherId = 1000000;
        defaultExpireTime = 3 days;
        maxVoucherValuePerAccount = 500000000000000000000000000000000;
    }

    function distributeVoucher(
        address _to,
        uint8 _voucherType,
        uint256 _value,
        uint256 _maxDiscountValue
    ) external onlyMiner returns (Voucher memory, uint256) {
        if (_voucherType == 1) {
            voucherValuePerAccount[_to] += _maxDiscountValue;
            require(
                voucherValuePerAccount[_to] <= maxVoucherValuePerAccount,
                "max value exceeded"
            );
        } else {
            voucherValuePerAccount[_to] += _value;
            require(
                voucherValuePerAccount[_to] <= maxVoucherValuePerAccount,
                "max value exceeded"
            );
        }

        globalVoucherId++;
        _mint(_to, globalVoucherId);
        voucherInfo[globalVoucherId] = Voucher({
            id: globalVoucherId,
            owner: _to,
            value: _value,
            expiredTime: 0,
            maxDiscountValue: _maxDiscountValue,
            voucherType: _voucherType,
            isActive: false
        });
        emit VoucherDistributed(
            _to,
            _value,
            _maxDiscountValue,
            _voucherType,
            globalVoucherId
        );
        return (voucherInfo[globalVoucherId], globalVoucherId);
    }

    function claim(uint256 _voucherId)
        external
        returns (uint256 voucherId, uint256 expiredTime)
    {
        return _claim(_voucherId, msg.sender, true);
    }

    function claimAll() external {
        address sender = msg.sender;
        uint256 balance = balanceOf(sender);

        for (uint256 i = 0; i < balance; i++) {
            uint256 voucherId = tokenOfOwnerByIndex(sender, i);
            _claim(voucherId, sender, false);
        }
    }

    function _claim(
        uint256 _voucherId,
        address _account,
        bool _revertOnActive
    ) private returns (uint256 voucherId, uint256 expiredTime) {
        Voucher storage voucher = voucherInfo[_voucherId];
        require(voucher.owner == _account, "not owner");

        if (_revertOnActive) {
            require(!voucher.isActive, "must be inactive");
        } else if (voucher.isActive) {
            return (0, 0);
        }

        uint256 expiredTime = block.timestamp +
            getExpireTime(voucher.voucherType);

        voucher.expiredTime = expiredTime;
        voucher.isActive = true;

        emit VoucherClaim(_account, _voucherId, expiredTime);
        return (_voucherId, expiredTime);
    }

    function burnVoucher(uint256 voucherId) public onlyMiner {
        require(_isApprovedOrOwner(_msgSender(), globalVoucherId), "!Burn");
        _burn(globalVoucherId);
        emit VoucherBurned(voucherInfo[globalVoucherId].owner, globalVoucherId);
    }

    function tokenIdsByOwner(address owner)
        external
        view
        returns (uint256[] memory)
    {
        uint256 balance = balanceOf(owner);
        uint256[] memory tokens = new uint256[](balance);

        for (uint256 i = 0; i < balance; i++) {
            tokens[i] = tokenOfOwnerByIndex(owner, i);
        }

        return tokens;
    }

    function tokensByOwner(address owner)
        external
        view
        returns (Voucher[] memory)
    {
        uint256 balance = balanceOf(owner);
        Voucher[] memory vouchers = new Voucher[](balance);

        for (uint256 i = 0; i < balance; i++) {
            uint256 voucherId = tokenOfOwnerByIndex(owner, i);
            vouchers[i] = voucherInfo[voucherId];
        }

        return vouchers;
    }

    function addOperator(address _miner) public onlyOwner {
        miner[_miner] = true;
    }

    function revokeOperator(address _miner) public onlyOwner {
        miner[_miner] = false;
    }

    function getExpireTime(uint8 _voucherType) public view returns (uint256) {
        uint256 expiredTime = expireTimeMap[_voucherType];
        return expiredTime > 0 ? expiredTime : defaultExpireTime;
    }

    function getVoucherInfo(uint256 _voucherId)
        external
        view
        returns (Voucher memory)
    {
        return voucherInfo[_voucherId];
    }

    function setExpireTime(uint8 _voucherType, uint256 _expiredTimeInSecond)
        external
        onlyOwner
    {
        expireTimeMap[_voucherType] = _expiredTimeInSecond;
    }

    function setMaxVoucherValuePerAccount(uint256 _amount) external onlyOwner {
        maxVoucherValuePerAccount = _amount;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        if (from == address(0) || to == address(0)) {
            return;
        }
        require(
            from == futurXGateway || to == futurXGateway,
            "Transfer is not allow"
        );
    }
}
