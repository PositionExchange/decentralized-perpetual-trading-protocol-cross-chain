// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IFeeRebateVoucherStrategy {
    function applyVoucher(uint256 voucherId, address user) external;

    function revokeVoucherApplying(address user) external;

    function calculateFeeRebate(
        address user,
        uint256 amount
    ) external view returns (uint256);

    function usingStrategy(
        address user,
        uint256 amount
    ) external returns (uint256);

    function userVoucherApplying(address user) external view returns (uint256);
}
