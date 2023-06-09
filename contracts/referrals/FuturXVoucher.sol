/**
 * @author Musket
 */
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/SignatureCheckerUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "../interfaces/IFuturXVoucher.sol";

contract FuturXVoucher is ERC721EnumerableUpgradeable, OwnableUpgradeable {
    struct Voucher {
        uint256 id;
        address owner;
        uint256 value;
        uint256 expiredTime;
        uint256 maxDiscountValue;
        uint8 voucherType;
        bool isActive;
    }

    struct ClaimRequest {
        uint256 voucherId;
        address to;
        uint8 voucherType;
        uint256 value;
        uint256 maxDiscountValue;
        bytes signature;
    }

    address public futurXGateway;
    address public signer;

    mapping(uint256 => Voucher) public voucherInfo;

    uint256 public defaultExpireTime;
    mapping(uint8 => uint256) public expireTimeMap;

    mapping(address => uint256) public voucherValuePerAccount;
    uint256 public maxVoucherValuePerAccount;

    event VoucherClaim(
        address owner,
        uint256 value,
        uint256 expiredTime,
        uint256 maxDiscountValue,
        uint8 voucherType,
        uint256 voucherId
    );

    event VoucherBurned(address owner, uint256 voucherId);

    modifier onlyFuturXGateway() {
        require(msg.sender == futurXGateway, "Voucher: 403");
        _;
    }

    function initialize(address _futurXGateway, address _signer)
        public
        initializer
    {
        __Ownable_init();
        __ERC721_init("FuturX Voucher", "FV");

        futurXGateway = _futurXGateway;
        signer = _signer;

        defaultExpireTime = 3 days;
        maxVoucherValuePerAccount = 500000000000000000000000000000000;
    }

    function claim(ClaimRequest[] memory requests) external {
        for (uint256 i = 0; i < requests.length; i++) {
            ClaimRequest memory request = requests[i];
            // Validate signature
            bool isValid = isSignatureValid(
                request.voucherId,
                request.to,
                request.voucherType,
                request.value,
                request.maxDiscountValue,
                request.signature
            );
            require(isValid, "invalid signature");

            _claim(
                request.voucherId,
                request.to,
                request.voucherType,
                request.value,
                request.maxDiscountValue
            );
        }
    }

    function _claim(
        uint256 _voucherId,
        address _to,
        uint8 _voucherType,
        uint256 _value,
        uint256 _maxDiscountValue
    ) private returns (uint256) {
        if (_voucherType == 1) {
            voucherValuePerAccount[_to] += _maxDiscountValue;
            require(
                voucherValuePerAccount[_to] <= maxVoucherValuePerAccount,
                "max value exceeded"
            );
        } else {
            voucherValuePerAccount[_to] += _value;
            require(
                voucherValuePerAccount[_to] <= maxVoucherValuePerAccount,
                "max value exceeded"
            );
        }

        _mint(_to, _voucherId);
        uint256 expiredTime = block.timestamp + getExpireTime(_voucherType);
        voucherInfo[_voucherId] = Voucher({
            id: _voucherId,
            owner: _to,
            value: _value,
            expiredTime: expiredTime,
            maxDiscountValue: _maxDiscountValue,
            voucherType: _voucherType,
            isActive: true
        });
        emit VoucherClaim(
            _to,
            _value,
            expiredTime,
            _maxDiscountValue,
            _voucherType,
            _voucherId
        );
        return (_voucherId);
    }

    function burnVoucher(uint256 voucherId) public onlyOwner {
        require(_isApprovedOrOwner(_msgSender(), voucherId), "!Burn");
        _burn(voucherId);
        emit VoucherBurned(voucherInfo[voucherId].owner, voucherId);
    }

    function tokenIdsByOwner(address owner)
        external
        view
        returns (uint256[] memory)
    {
        uint256 balance = balanceOf(owner);
        uint256[] memory tokens = new uint256[](balance);

        for (uint256 i = 0; i < balance; i++) {
            tokens[i] = tokenOfOwnerByIndex(owner, i);
        }

        return tokens;
    }

    function tokensByOwner(address owner)
        external
        view
        returns (Voucher[] memory)
    {
        uint256 balance = balanceOf(owner);
        Voucher[] memory vouchers = new Voucher[](balance);

        for (uint256 i = 0; i < balance; i++) {
            uint256 voucherId = tokenOfOwnerByIndex(owner, i);
            vouchers[i] = voucherInfo[voucherId];
        }

        return vouchers;
    }

    function getExpireTime(uint8 _voucherType) public view returns (uint256) {
        uint256 expiredTime = expireTimeMap[_voucherType];
        return expiredTime > 0 ? expiredTime : defaultExpireTime;
    }

    function getVoucherInfo(uint256 _voucherId)
        external
        view
        returns (Voucher memory)
    {
        return voucherInfo[_voucherId];
    }

    function isSignatureValid(
        uint256 _voucherId,
        address _to,
        uint8 _voucherType,
        uint256 _value,
        uint256 _maxDiscountValue,
        bytes memory _signature
    ) public view returns (bool) {
        bytes32 messageHash = getMessageHash(
            _voucherId,
            _to,
            _voucherType,
            _value,
            _maxDiscountValue
        );
        return
            SignatureCheckerUpgradeable.isValidSignatureNow(
                signer,
                getSignedMessageHash(messageHash),
                _signature
            );
    }

    function getMessageHash(
        uint256 _voucherId,
        address _to,
        uint8 _voucherType,
        uint256 _value,
        uint256 _maxDiscountValue
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    _voucherId,
                    _to,
                    _voucherType,
                    _value,
                    _maxDiscountValue
                )
            );
    }

    function getSignedMessageHash(bytes32 hash) public pure returns (bytes32) {
        return ECDSAUpgradeable.toEthSignedMessageHash(hash);
    }

    function setExpireTime(uint8 _voucherType, uint256 _expiredTimeInSecond)
        external
        onlyOwner
    {
        expireTimeMap[_voucherType] = _expiredTimeInSecond;
    }

    function setMaxVoucherValuePerAccount(uint256 _amount) external onlyOwner {
        maxVoucherValuePerAccount = _amount;
    }

    function setSigner(address _address) external onlyOwner {
        signer = _address;
    }

    function reActivate(uint256 _voucherId) external onlyFuturXGateway {
        voucherInfo[_voucherId].isActive = true;
    }

    function deactivate(uint256 _voucherId) external onlyFuturXGateway {
        voucherInfo[_voucherId].isActive = false;
    }

    function setFuturXGateway(address _address) external onlyOwner {
        futurXGateway = _address;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721EnumerableUpgradeable ) {
        super._beforeTokenTransfer(from, to, tokenId, 1);
//        super._beforeTokenTransfer(from, to, tokenId);

        if (from == address(0) || to == address(0)) {
            return;
        }
        require(
            from == futurXGateway || to == futurXGateway,
            "Transfer is not allow"
        );
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId)
        internal
        view
        override
        returns (bool)
    {
        return true;
    }
}
