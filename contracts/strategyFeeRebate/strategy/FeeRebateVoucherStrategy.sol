/**
 * @author Musket
 */
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721EnumerableUpgradeable.sol";
import "../interfaces/IFeeRebateVoucher.sol";
import "../FeeRebateVoucher.sol";

contract FeeRebateVoucherStrategy is OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {


    mapping(address => bool) public handlers;

    mapping(address => uint256) public uerVoucherApplying;

    IFeeRebateVoucher  public voucherFeeRebateToken;

    address public futurXGateway;


    modifier onlyHandler() {
        require(handlers[msg.sender], "!handler");
        _;
    }



    function initialize(
        address _futurXGateway
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        futurXGateway = _futurXGateway;
        handlers[_futurXGateway] = true;
        handlers[msg.sender] = true;
    }



    function calculateFeeRebate(uint256 voucherId, uint256 amount) public view returns (uint256 feeRebate, FeeRebateVoucher.VoucherInfo memory voucher) {

        (
            voucher.id,
            voucher.owner,
            voucher.value,
            voucher.remainValue,
            voucher.expiredTime,
            voucher.discountPercent
        ) = voucherFeeRebateToken.voucherInfo(voucherId);

        if (voucher.expiredTime >= block.timestamp) {
            feeRebate = (amount * voucher.discountPercent) / 10000;
            if (feeRebate > voucher.remainValue) {
                feeRebate = voucher.remainValue;
            }
        }

        return (feeRebate, voucher);
    }


    function applyVoucher(uint256 voucherId, address user) external onlyHandler {

        revokeVoucherApplying(user);
        require(!voucherFeeRebateToken.isExpired(voucherId), "Voucher is expired");
        voucherFeeRebateToken.safeTransferFrom(user, futurXGateway, voucherId);
        uerVoucherApplying[user] = voucherId;
    }

    function revokeVoucherApplying(address user) public onlyHandler {

        uint256 _oldVoucherId = uerVoucherApplying[user];

        if (_oldVoucherId > 0) {
            bool _isExpired = voucherFeeRebateToken.isExpired(_oldVoucherId);

            if (_isExpired) {
                voucherFeeRebateToken.burnVoucher(_oldVoucherId);

            }else {
                voucherFeeRebateToken.safeTransferFrom(futurXGateway, user, _oldVoucherId);
            }
            uerVoucherApplying[user] = 0;
        }
    }


    function usingVoucher(address user, uint256 amount) external onlyHandler returns (uint256){

        uint256 voucherId = uerVoucherApplying[user];

        if (voucherId == 0) {
            return 0;
        }

        (
            uint256 feeRebate,
            FeeRebateVoucher.VoucherInfo memory voucher
        ) = calculateFeeRebate(voucherId, amount);

        if (voucher.expiredTime < block.timestamp || feeRebate == voucher.remainValue) {
            voucherFeeRebateToken.burnVoucher(voucherId);
            uerVoucherApplying[user] = 0;
        }
        if (feeRebate < voucher.remainValue) {
            voucherFeeRebateToken.updateVoucher(voucherId, voucher.remainValue - feeRebate);
        }
        return feeRebate;
    }


    function setHandler(address handler, bool status) external onlyOwner {
        handlers[handler] = status;
    }

    function setVoucherFeeRebateToken(IFeeRebateVoucher _voucherFeeRebateToken) external onlyOwner {
        voucherFeeRebateToken = _voucherFeeRebateToken;
    }


}
