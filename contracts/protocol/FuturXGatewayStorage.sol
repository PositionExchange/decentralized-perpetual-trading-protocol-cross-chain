// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@positionex/position-helper/contracts/utils/Require.sol";
import "../interfaces/IFuturXGatewayStorage.sol";

contract FuturXGatewayStorage is IFuturXGatewayStorage, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;

    address public futurXGateway;

    mapping(address => uint256) public updateCollateralIndex;
    mapping(bytes32 => AddCollateralRequest) public updateCollateralRequests;
    bytes32[] public updateCollateralRequestKeys;

    modifier onlyFuturXGateway() {
        Require._require(
            msg.sender == futurXGateway,
            "FuturXGatewayStorage: 403"
        );
        _;
    }

    function initialize(address _futurXGateway) public initializer {
        __Ownable_init();
        futurXGateway = _futurXGateway;
    }

    function storeUpdateCollateralRequest(AddCollateralRequest memory _request)
        public
        onlyFuturXGateway
        returns (uint256, bytes32)
    {
        address account = _request.account;
        uint256 index = updateCollateralIndex[account].add(1);
        updateCollateralIndex[account] = index;
        bytes32 key = _getRequestKey(account, index);

        updateCollateralRequests[key] = _request;
        updateCollateralRequestKeys.push(key);

        return (index, key);
    }

    function getDeleteUpdateCollateralRequest(bytes32 _key)
        public
        onlyFuturXGateway
        returns (AddCollateralRequest memory request)
    {
        request = updateCollateralRequests[_key];
        Require._require(request.account != address(0), "FuturXGatewayStorage: 404");

        _deleteUpdateCollateralRequests(_key);
    }

    function _getRequestKey(address _account, uint256 _index)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_account, _index));
    }

    function _deleteUpdateCollateralRequests(bytes32 _key) private {
        delete updateCollateralRequests[_key];
    }
}
