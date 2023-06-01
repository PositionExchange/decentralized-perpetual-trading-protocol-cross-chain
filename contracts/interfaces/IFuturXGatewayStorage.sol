// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IFuturXGatewayStorage {
    struct AddCollateralRequest {
        address account;
        address[] path;
        address indexToken;
        uint256 amountInToken;
        bool isLong;
        uint256 feeToken;
    }

    function storeUpdateCollateralRequest(AddCollateralRequest memory _request)
        external
        returns (uint256, bytes32);

    function getDeleteUpdateCollateralRequest(bytes32 _key)
        external
        returns (AddCollateralRequest memory);
}
