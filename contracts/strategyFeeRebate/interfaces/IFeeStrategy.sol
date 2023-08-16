// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IFeeStrategy {
    enum TypeStrategy {None, FeeRebateVoucherStrategy, HoldingToFeeRebate}

    function applyVoucher(uint256 voucherId, address user) external;

    function revokeVoucherApplying(address user) external;

    function calculateFeeRebate(address user, uint256 amount) external view returns (uint256);

    function usingStrategy(address user, uint256 amount) external returns (uint256);

    function setActiveType(TypeStrategy _activeType) external;

    function setStrategy(TypeStrategy _type, address _strategy) external;

    function mappingTypeToStrategy(TypeStrategy typeStrategy) external view returns (address);

    function activeType() external view returns (TypeStrategy);
}
