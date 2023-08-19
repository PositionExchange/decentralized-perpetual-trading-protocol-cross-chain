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

    mapping(address => bool) public handlers;

    event FeeRebated(address user, uint256 feeRebated, IFeeStrategy.TypeStrategy typeStrategy);

    modifier onlyHandler() {
        require(handlers[msg.sender], "!handler FeeStrategy");
        _;
    }

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

    function setHandler(address _handler, bool status) external onlyOwner {
        handlers[_handler] = status;
    }

    function usingStrategy(
        address user,
        uint256 amount
    ) external onlyHandler returns (uint256) {
        IFeeStrategy.TypeStrategy _activeType = activeType;
        if (_activeType == IFeeStrategy.TypeStrategy.None) return 0;

        uint256 feeRebate = IFeeRebateStrategy(mappingTypeToStrategy[_activeType]).usingStrategy(
                user,
                amount
            );

        emit FeeRebate(user, feeRebate, _activeType);
        return feeRebate;
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
