// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./interfaces/IFeeRebateVoucherStrategy.sol";
import "./interfaces/IFeeStrategy.sol";
import "./FeeRebateVoucher.sol";

contract FeeStrategy is IFeeStrategy, OwnableUpgradeable {
    mapping(IFeeStrategy.TypeStrategy => address)
        public
        override mappingTypeToStrategy;

    // 1 using FeeRebateVoucherStrategy
    // 2 using HoldingToFeeRebate
    IFeeStrategy.TypeStrategy public override activeType;

    mapping(address => bool) public handlers;

    event FeeRebated(
        address user,
        uint256 feeRebated,
        IFeeStrategy.TypeStrategy typeStrategy
    );

    event VoucherRevoked(address user);

    event VoucherApplied(address user, uint256 voucherId);

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

        uint256 feeRebate = IFeeRebateVoucherStrategy(
            mappingTypeToStrategy[_activeType]
        ).usingStrategy(user, amount);

        if (feeRebate == 0) return 0;

        emit FeeRebated(user, feeRebate, _activeType);
        return feeRebate;
    }

    function applyVoucher(uint256 voucherId, address user) external {
        require(
            activeType == IFeeStrategy.TypeStrategy.FeeRebateVoucherStrategy,
            "FeeStrategy: required FeeRebateVoucherStrategy"
        );
        IFeeRebateVoucherStrategy(mappingTypeToStrategy[activeType])
            .applyVoucher(voucherId, user);
        emit VoucherApplied(user, voucherId);
    }

    function revokeVoucherApplying(address user) external {
        require(
            activeType == IFeeStrategy.TypeStrategy.FeeRebateVoucherStrategy,
            "FeeStrategy: required FeeRebateVoucherStrategy"
        );
        IFeeRebateVoucherStrategy(mappingTypeToStrategy[activeType])
            .revokeVoucherApplying(user);
        emit VoucherRevoked(user);
    }

    function calculateFeeRebate(
        address user,
        uint256 amount
    ) external view returns (uint256) {
        return
            IFeeRebateVoucherStrategy(mappingTypeToStrategy[activeType])
                .calculateFeeRebate(user, amount);
    }

    function currentApplying(
        address user
    ) external view returns (FeeRebateVoucher.VoucherInfo memory info) {

        info = IFeeRebateVoucherStrategy(mappingTypeToStrategy[activeType])
                .getVoucherInfo(user);

//        return
//            IFeeRebateVoucherStrategy(mappingTypeToStrategy[activeType])
//                .getVoucherInfo(user);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[46] private __gap;
}
