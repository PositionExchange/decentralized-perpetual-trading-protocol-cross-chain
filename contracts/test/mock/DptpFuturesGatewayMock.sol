// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

import "../../protocol/DptpFuturesGateway.sol";

contract DptpFuturesGatewayMock is DptpFuturesGateway {
    function calculateMarginFees(
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta,
        uint256 _amountIn,
        uint256 _leverage
    ) public returns (uint256) {
        return
            _calculateMarginFees(
                _collateralToken,
                _indexToken,
                _isLong,
                _amountIn,
                _leverage
            );
    }
}
