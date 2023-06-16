// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../staking/interfaces/IVester.sol";
import "../staking/interfaces/IRewardTracker.sol";

contract EsPosiBatchSender {
    using SafeMath for uint256;

    address public admin;
    address public esPosi;

    constructor(address _esPosi) public {
        admin = msg.sender;
        esPosi = _esPosi;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "EsPosiBatchSender: forbidden");
        _;
    }

    function send(
        IVester _vester,
        uint256 _minRatio,
        address[] memory _accounts,
        uint256[] memory _amounts
    ) external onlyAdmin {
        IRewardTracker rewardTracker = IRewardTracker(_vester.rewardTracker());

        for (uint256 i = 0; i < _accounts.length; i++) {
            IERC20(esPosi).transferFrom(msg.sender, _accounts[i], _amounts[i]);

            uint256 nextTransferredCumulativeReward = _vester
                .transferredCumulativeRewards(_accounts[i])
                .add(_amounts[i]);
            _vester.setTransferredCumulativeRewards(
                _accounts[i],
                nextTransferredCumulativeReward
            );

            uint256 cumulativeReward = rewardTracker.cumulativeRewards(
                _accounts[i]
            );
            uint256 totalCumulativeReward = cumulativeReward.add(
                nextTransferredCumulativeReward
            );

            uint256 combinedAverageStakedAmount = _vester
                .getCombinedAverageStakedAmount(_accounts[i]);

            if (
                combinedAverageStakedAmount >
                totalCumulativeReward.mul(_minRatio)
            ) {
                continue;
            }

            uint256 nextTransferredAverageStakedAmount = _minRatio.mul(
                totalCumulativeReward
            );
            nextTransferredAverageStakedAmount = nextTransferredAverageStakedAmount
                .sub(
                    rewardTracker
                        .averageStakedAmounts(_accounts[i])
                        .mul(cumulativeReward)
                        .div(totalCumulativeReward)
                );

            nextTransferredAverageStakedAmount = nextTransferredAverageStakedAmount
                .mul(totalCumulativeReward)
                .div(nextTransferredCumulativeReward);

            _vester.setTransferredAverageStakedAmounts(
                _accounts[i],
                nextTransferredAverageStakedAmount
            );
        }
    }
}
