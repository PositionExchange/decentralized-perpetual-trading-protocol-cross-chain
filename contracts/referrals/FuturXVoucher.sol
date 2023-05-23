/**
 * @author Musket
 */
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract FuturXVoucher is ERC721Enumerable, Ownable {
    struct Voucher {
        address owner;
        uint256 value;
        uint256 expiredTime;
        uint256 maxDiscountValue;
        uint8 voucherType;
        bool isActive;
    }

    mapping(uint256 => Voucher) public voucherInfo;
    mapping(address => bool) public miner;

    uint256 public voucherID = 1000000;
    uint256 public defaultExpireTime = 3 days;
    mapping(uint8 => uint256) expireTimeMap;

    event VoucherDistributed(
        address owner,
        uint256 value,
        uint256 expiredTime,
        uint256 maxDiscountValue,
        uint8 voucherType,
        uint256 voucherID
    );

    event VoucherClaim(address owner, uint256 voucherID, uint256 expiredTime);

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
        uint256 _expiredTime,
        uint256 _maxDiscountValue
    ) external onlyMiner returns (Voucher memory, uint256 voucherId) {
        voucherID++;
        _mint(_to, voucherID);
        voucherInfo[voucherID] = Voucher({
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
            _expiredTime,
            _maxDiscountValue,
            _voucherType,
            voucherID
        );
        return (voucherInfo[voucherID], voucherID);
    }

    function claim(uint256 _voucherID)
        external
        returns (uint256 voucherId, uint256 expiredTime)
    {
        return _claim(_voucherID, msg.sender);
    }

    // TODO: Liam must check this function
//    function claimAll() external {
//        address sender = msg.sender;
//        uint256 balance = balanceOf(sender);
//
//        for (uint256 i = 0; i < balance; i++) {
//            uint256 voucherID = tokenOfOwnerByIndex(owner, i);
//            _claim(voucherID, sender);
//        }
//    }

    function _claim(uint256 _voucherID, address _account)
        private
        returns (uint256 voucherId, uint256 expiredTime)
    {
        Voucher storage voucher = voucherInfo[_voucherID];
        require(voucher.owner == _account, "not owner");

        uint256 expiredTime = block.timestamp +
            getExpireTime(voucher.voucherType);

        voucher.expiredTime = expiredTime;
        voucher.isActive = true;

        emit VoucherClaim(_account, _voucherID, expiredTime);
        return (_voucherID, expiredTime);
    }

    function burnVoucher(uint256 voucherId) public onlyMiner {
        require(_isApprovedOrOwner(_msgSender(), voucherId), "!Burn");
        _burn(voucherId);
        emit VoucherBurned(voucherInfo[voucherId].owner, voucherId);
    }

    function tokensOfOwner(address owner)
        public
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

    function setExpireTime(uint8 _voucherType, uint256 _expiredTimeInSecond)
        external
        onlyOwner
    {
        expireTimeMap[_voucherType] = _expiredTimeInSecond;
    }
}
