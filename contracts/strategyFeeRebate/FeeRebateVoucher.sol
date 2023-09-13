/**
 * @author Musket
 */
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

contract FeeRebateVoucher is ERC721EnumerableUpgradeable, OwnableUpgradeable {
    mapping(address => bool) public handlers;

    uint256 public voucherId;

    mapping(uint256 => VoucherInfo) public voucherInfo;

    address public futurXGateway;

    modifier onlyHandler() {
        require(handlers[msg.sender], "!handler Voucher");
        _;
    }

    struct VoucherInfo {
        uint256 id;
        address owner;
        uint256 value;
        uint256 remainValue;
        uint256 expiredTime;
        uint256 discountPercent;
    }

    event VoucherClaimed(
        address owner,
        uint256 value,
        uint256 expiredTime,
        uint256 discountPercent,
        uint256 voucherId
    );

    event VoucherBurned(address owner, uint256 voucherId);

    function initialize(address _futurXGateway) public initializer {
        __Ownable_init();
        __ERC721_init("FuturX Fee Rebate Voucher", "FFRV");
        futurXGateway = _futurXGateway;
        voucherId = 1000000;
    }

    function mint(
        address to,
        uint256 value,
        uint256 duration,
        uint256 discountPercent
    ) external onlyHandler returns (uint256) {
        uint256 _voucherId = voucherId++;

        _mint(to, _voucherId);
        voucherInfo[_voucherId] = VoucherInfo({
            id: _voucherId,
            owner: to,
            value: value,
            remainValue: value,
            expiredTime: block.timestamp + duration,
            discountPercent: discountPercent
        });

        emit VoucherClaimed(
            to,
            value,
            block.timestamp + duration,
            discountPercent,
            voucherId
        );
        return (_voucherId);
    }

    function burnVoucher(uint256 voucherId) public onlyHandler {
        require(_isApprovedOrOwner(_msgSender(), voucherId), "!Burn");
        _burn(voucherId);
        emit VoucherBurned(voucherInfo[voucherId].owner, voucherId);
    }

    function updateVoucher(
        uint256 voucherId,
        uint256 remainValue
    ) public onlyHandler {
        voucherInfo[voucherId].remainValue = remainValue;
    }

    function isExpired(uint256 voucherId) public view returns (bool) {
        return voucherInfo[voucherId].expiredTime < block.timestamp;
    }

    function tokenIdsByOwner(
        address owner
    ) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(owner);
        uint256[] memory tokens = new uint256[](balance);

        for (uint256 i = 0; i < balance; i++) {
            tokens[i] = tokenOfOwnerByIndex(owner, i);
        }

        return tokens;
    }

    function tokensByOwner(
        address owner
    ) external view returns (VoucherInfo[] memory) {
        uint256 balance = balanceOf(owner);
        VoucherInfo[] memory vouchers = new VoucherInfo[](balance);

        for (uint256 i = 0; i < balance; i++) {
            uint256 voucherId = tokenOfOwnerByIndex(owner, i);
            vouchers[i] = voucherInfo[voucherId];
        }

        return vouchers;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721EnumerableUpgradeable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);

        if (from == address(0) || to == address(0)) {
            return;
        }
        require(
            from == futurXGateway || to == futurXGateway,
            "Transfer is not allow"
        );
    }

    function _isApprovedOrOwner(
        address spender,
        uint256 tokenId
    ) internal view override returns (bool) {
        return true;
    }

    function setHandler(address handler, bool status) external onlyOwner {
        handlers[handler] = status;
    }

    function setFuturXGateway(address _futurXGateway) external onlyOwner {
        futurXGateway = _futurXGateway;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[46] private __gap;
}