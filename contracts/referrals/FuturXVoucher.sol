/**
 * @author Musket
 */
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "../interfaces/IFuturXVoucher.sol";

contract FuturXVoucher is ERC721Enumerable, Ownable {
    struct Voucher {
        uint256 id;
        address owner;
        uint256 value;
        uint256 expiredTime;
        uint256 maxDiscountValue;
        uint8 voucherType;
        bool isActive;
    }

    mapping(uint256 => Voucher) public voucherInfo;
    mapping(address => bool) public miner;

    uint256 public globalVoucherId = 1000000;
    uint256 public defaultExpireTime = 3 days;
    mapping(uint8 => uint256) public expireTimeMap;

    mapping(address => uint256) public voucherValuePerAccount;
    uint256 public maxVoucherValuePerAccount = 500000000000000000000000000000000;

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

    constructor() ERC721("FuturX Voucher", "FV") {}

    function distributeVoucher(
        address _to,
        uint8 _voucherType,
        uint256 _value,
        uint256 _maxDiscountValue
    ) external onlyMiner returns (Voucher memory, uint256) {

        if (_voucherType == 1) {
            voucherValuePerAccount[_to] += _maxDiscountValue;
            require(voucherValuePerAccount[_to] <= maxVoucherValuePerAccount, "max value exceeded");
        } else {
            voucherValuePerAccount[_to] += _value;
            require(voucherValuePerAccount[_to] <= maxVoucherValuePerAccount, "max value exceeded");
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
            _claim(globalVoucherId, sender, false);
        }
    }

    function _claim(uint256 _voucherId, address _account, bool _revertOnActive)
        private
        returns (uint256 voucherId, uint256 expiredTime)
    {
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

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override {
        revert("Not allow");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
//    function safeTransferFrom(
//        address from,
//        address to,
//        uint256 tokenId,
//        bytes memory data
//    ) public override {
//        if (from)
//        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner or approved");
//        _safeTransfer(from, to, tokenId, data);
//    }

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

    function getVoucherInfo(uint256 _voucherId) external view returns (Voucher memory) {
        return voucherInfo[_voucherId];
    }

    function setExpireTime(uint8 _voucherType, uint256 _expiredTimeInSecond)
        external
        onlyOwner
    {
        expireTimeMap[_voucherType] = _expiredTimeInSecond;
    }

    function setMaxVoucherValuePerAccount(uint256 _amount)
        external
        onlyOwner
    {
        maxVoucherValuePerAccount = _amount;
    }
}
