// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "../../referrals/interfaces/IReferralRewardTracker.sol";

contract ReferralRewardTrackerMock is IReferralRewardTracker {
    function updateClaimableReward(address _trader, uint256 _fee) external {}

    function updateRefereeStatus(
        address _trader,
        address _indexToken,
        uint256 _timestamp,
        uint256 _notional,
        bool _isIncrease
    ) external {}
}
