/**
 * @author Musket
 */
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721EnumerableUpgradeable.sol";

import {NumberHelper} from "../../protocol/libraries/helpers/NumberHelper.sol";
import "../interfaces/IFeeRebateVoucher.sol";
import "../interfaces/IFeeRebateStrategy.sol";
import "../FeeRebateVoucher.sol";

contract FeeRebateVoucherStrategy is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    mapping(address => bool) public handlers;

    mapping(address => uint256) public userVoucherApplying;

    IFeeRebateVoucher public voucherFeeRebateToken;

    address public futurXGateway;

    modifier onlyHandler() {
        require(handlers[msg.sender], "!handler");
        _;
    }

    function initialize(address _futurXGateway) public initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        futurXGateway = _futurXGateway;
        handlers[_futurXGateway] = true;
        handlers[msg.sender] = true;
    }

    function applyVoucher(
        uint256 voucherId,
        address user
    ) external onlyHandler {
        revokeVoucherApplying(user);
        require(
            !voucherFeeRebateToken.isExpired(voucherId),
            "Voucher is expired"
        );
        voucherFeeRebateToken.safeTransferFrom(user, futurXGateway, voucherId);
        userVoucherApplying[user] = voucherId;
    }

    function revokeVoucherApplying(address user) public onlyHandler {
        uint256 _oldVoucherId = userVoucherApplying[user];

        if (_oldVoucherId > 0) {
            bool _isExpired = voucherFeeRebateToken.isExpired(_oldVoucherId);

            if (_isExpired) {
                voucherFeeRebateToken.burnVoucher(_oldVoucherId);
            } else {
                voucherFeeRebateToken.safeTransferFrom(
                    futurXGateway,
                    user,
                    _oldVoucherId
                );
            }
            userVoucherApplying[user] = 0;
        }
    }

    function usingStrategy(
        address user,
        uint256 amount
    ) external onlyHandler returns (uint256) {
        uint256 voucherId = userVoucherApplying[user];

        if (voucherId == 0) {
            return 0;
        }

        (
            uint256 feeRebate,
            FeeRebateVoucher.VoucherInfo memory voucher
        ) = _calculateFeeRebateAndVoucherInfo(voucherId, amount);

        if (
            voucher.expiredTime < block.timestamp ||
            feeRebate == voucher.remainValue
        ) {
            voucherFeeRebateToken.burnVoucher(voucherId);
            userVoucherApplying[user] = 0;
        }
        if (feeRebate < voucher.remainValue) {
            voucherFeeRebateToken.updateVoucher(
                voucherId,
                voucher.remainValue - feeRebate
            );
        }
        return feeRebate;
    }

    function calculateFeeRebate(
        address user,
        uint256 amount
    ) external view returns (uint256) {
        uint256 feeRebate;
        FeeRebateVoucher.VoucherInfo memory voucher = getVoucherInfo(user);

        if (voucher.expiredTime >= block.timestamp) {
            feeRebate = (amount * voucher.discountPercent) / 10000;
            if (feeRebate > voucher.remainValue) {
                feeRebate = voucher.remainValue;
            }
        }

        return feeRebate;
    }

    function getVoucherInfo(
        address user
    ) public view returns (FeeRebateVoucher.VoucherInfo memory voucher) {
        (
            voucher.id,
            voucher.owner,
            voucher.value,
            voucher.remainValue,
            voucher.expiredTime,
            voucher.discountPercent
        ) = voucherFeeRebateToken.voucherInfo(userVoucherApplying[user]);

        return voucher;
    }

    function setHandler(address handler, bool status) external onlyOwner {
        handlers[handler] = status;
    }

    function setVoucherFeeRebateToken(
        IFeeRebateVoucher _voucherFeeRebateToken
    ) external onlyOwner {
        voucherFeeRebateToken = _voucherFeeRebateToken;
    }

    /// PRIVATE FUNCTION
    function _calculateFeeRebateAndVoucherInfo(
        uint256 voucherId,
        uint256 amount
    )
        internal
        view
        returns (uint256 feeRebate, FeeRebateVoucher.VoucherInfo memory voucher)
    {
        (
            voucher.id,
            voucher.owner,
            voucher.value,
            voucher.remainValue,
            voucher.expiredTime,
            voucher.discountPercent
        ) = voucherFeeRebateToken.voucherInfo(voucherId);

        if (voucher.expiredTime >= block.timestamp) {
            feeRebate =
                (amount * voucher.discountPercent) /
                NumberHelper.BASIC_POINT_FEE;
            if (feeRebate > voucher.remainValue) {
                feeRebate = voucher.remainValue;
            }
        }

        return (feeRebate, voucher);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[46] private __gap;
}
