/**
 * @author Musket
 */
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract FuturXVoucher is ERC721, Ownable {

    struct Voucher {
        address owner;
        uint256 value;
        uint256 expiredDate;
        uint256 maxDiscountValue;
        uint8 typeVoucher;
    }

    mapping(uint256 => Voucher) public voucherInfo;
    mapping(address => bool) public miner;

    uint256 public voucherID = 1000000;

    event VoucherDistributed(
        address owner,
        uint256 value,
        uint256 expiredDate,
        uint256 maxDiscountValue,
        uint8 typeVoucher,
        uint256 voucherID
    );

    event VoucherBurned(
        address owner,
        uint256 voucherId
    );


    modifier onlyMiner() {
        require(miner[msg.sender], "Only miner");
        _;
    }

    constructor() ERC721("FuturX Voucher", "FV"){}


    function distributeVoucher(
        address _to,
        uint8 _typeVoucher,
        uint256 _value,
        uint256 _expiredDate,
        uint256 _maxDiscountValue
    ) public onlyMiner returns (Voucher memory, uint256 voucherId)  {
        voucherID++;
        _mint(_to, voucherID);
        voucherInfo[voucherID] = Voucher(
            {
                owner: _to,
                value: _value,
                expiredDate: _expiredDate,
                maxDiscountValue: _maxDiscountValue,
                typeVoucher: _typeVoucher
            }
        );
        emit VoucherDistributed(_to, _value, _expiredDate, _maxDiscountValue, _typeVoucher, voucherID);
        return (voucherInfo[voucherID], voucherID);
    }


    function burnVoucher(uint256 voucherId) public onlyMiner {
        require(_isApprovedOrOwner(_msgSender(), voucherId), "!Burn");
        _burn(voucherId);
        emit VoucherBurned(voucherInfo[voucherId].owner, voucherId);

    }

    function addOperator(address _miner) public onlyOwner {
        miner[_miner] = true;
    }

    function revokeOperator(address _miner) public onlyOwner {
        miner[_miner] = false;
    }

}
