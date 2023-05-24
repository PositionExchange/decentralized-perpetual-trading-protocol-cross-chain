pragma solidity ^0.8.0;

import "../referrals/FuturXVoucher.sol";

interface IFuturXVoucher {
    function getVoucherInfo(uint256 _voucherId) external view returns (FuturXVoucher.Voucher memory);
}
