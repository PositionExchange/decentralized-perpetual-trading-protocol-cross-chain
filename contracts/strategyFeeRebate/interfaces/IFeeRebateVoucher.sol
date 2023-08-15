/**
 * @author Musket
 */
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721EnumerableUpgradeable.sol";

interface IFeeRebateVoucher is IERC721EnumerableUpgradeable {


    function voucherInfo(uint256 voucherId) external view returns (uint256, address, uint256, uint256, uint256, uint256);

    function updateVoucher(uint256 voucherId, uint256 remainValue) external;

    function burnVoucher(uint256 voucherId) external;

    function isExpired(uint256 voucherId) external view returns (bool);

}
