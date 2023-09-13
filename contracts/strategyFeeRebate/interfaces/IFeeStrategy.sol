// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../FeeRebateVoucher.sol";

interface IFeeStrategy {
    enum TypeStrategy {
        None,
        FeeRebateVoucherStrategy,
        HoldingToFeeRebate
    }

    function applyVoucher(uint256 voucherId, address user) external;

    function revokeVoucherApplying(address user) external;

    function usingStrategy(
        address user,
        uint256 amount
    ) external returns (uint256);

    function setActiveType(TypeStrategy _activeType) external;

    function setStrategy(TypeStrategy _type, address _strategy) external;

    function calculateFeeRebate(
        address user,
        uint256 amount
    ) external view returns (uint256);

    function currentApplying(
        address user
    ) external view returns (FeeRebateVoucher.VoucherInfo memory voucher);

    function mappingTypeToStrategy(
        TypeStrategy typeStrategy
    ) external view returns (address);

    function activeType() external view returns (TypeStrategy);
}