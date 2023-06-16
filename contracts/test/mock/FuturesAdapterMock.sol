// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "../../interfaces/CrosschainFunctionCallInterface.sol";

contract FuturesAdapterMock is CrosschainFunctionCallInterface {
    event CrossCall(
        uint256 destBcId,
        address destContract,
        uint8 destMethodID,
        bytes destFunctionCall
    );

    function crossBlockchainCall(
        uint256 _destBcId,
        address _destContract,
        uint8 _destMethodID,
        bytes calldata _destData
    ) external override {
        emit CrossCall(_destBcId, _destContract, _destMethodID, _destData);
    }
}
