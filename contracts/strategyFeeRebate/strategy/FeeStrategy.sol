// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import ".././interfaces/IFeeRebateStrategy.sol";
import ".././interfaces/IFeeStrategy.sol";

contract FeeStrategy is IFeeStrategy, OwnableUpgradeable {
    mapping(IFeeStrategy.TypeStrategy => address)
        public
        override mappingTypeToStrategy;

    // 1 using FeeRebateVoucherStrategy
    // 2 using HoldingToFeeRebate
    IFeeStrategy.TypeStrategy public override activeType;

    function initialize(
        IFeeStrategy.TypeStrategy _activeType
    ) public initializer {
        __Ownable_init();
        activeType = _activeType;
    }

    function setActiveType(
        IFeeStrategy.TypeStrategy _activeType
    ) external onlyOwner {
        activeType = _activeType;
    }

    function setStrategy(
        IFeeStrategy.TypeStrategy _type,
        address _strategy
    ) external onlyOwner {
        mappingTypeToStrategy[_type] = _strategy;
    }

    function usingStrategy(
        address user,
        uint256 amount
    ) external returns (uint256) {
        if (activeType == IFeeStrategy.TypeStrategy.None) return 0;
        return
            IFeeRebateStrategy(mappingTypeToStrategy[activeType]).usingStrategy(
                user,
                amount
            );
    }

    function applyVoucher(uint256 voucherId, address user) external {
        require(
            activeType == IFeeStrategy.TypeStrategy.FeeRebateVoucherStrategy,
            "FeeStrategy: required FeeRebateVoucherStrategy"
        );
        IFeeRebateStrategy(mappingTypeToStrategy[activeType]).applyVoucher(
            voucherId,
            user
        );
    }

    function revokeVoucherApplying(address user) external {
        require(
            activeType == IFeeStrategy.TypeStrategy.FeeRebateVoucherStrategy,
            "FeeStrategy: required FeeRebateVoucherStrategy"
        );
        IFeeRebateStrategy(mappingTypeToStrategy[activeType])
            .revokeVoucherApplying(user);
    }

    function calculateFeeRebate(
        address user,
        uint256 amount
    ) external view returns (uint256) {
        return
            IFeeRebateStrategy(mappingTypeToStrategy[activeType])
                .calculateFeeRebate(user, amount);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[46] private __gap;
}
