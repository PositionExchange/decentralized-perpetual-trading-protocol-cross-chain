// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IReferralStorage {
    function codes(bytes32 _code) external view returns (address);

    function traderCodes(address _account) external view returns (bytes32);

    function traderReferralCodes(
        address _account
    ) external view returns (bytes32);

    function referrerTiers(address _account) external view returns (uint256);

    function traderStatus(address _account) external view returns (bool);

    function setTier(
        uint256 _tierId,
        uint256 _totalRebate,
        uint256 _discountShare
    ) external;


    function getReferrerInfo(
        address _trader
    ) external view returns (address, uint256, uint256);

    function isStatusUpgradeable(address _trader) external view returns (bool);
}
