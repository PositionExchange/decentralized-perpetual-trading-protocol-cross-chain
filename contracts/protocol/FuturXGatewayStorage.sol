// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@positionex/position-helper/contracts/utils/Require.sol";
import "../interfaces/IFuturXGatewayStorage.sol";

contract FuturXGatewayStorage is IFuturXGatewayStorage, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;

    address public futurXGateway;

    mapping(address => uint256) public increasePositionsIndex;
    mapping(bytes32 => IncreasePositionRequest) public increasePositionRequests;
    bytes32[] public increasePositionRequestKeys;

    mapping(address => uint256) public decreasePositionsIndex;
    mapping(bytes32 => DecreasePositionRequest) public decreasePositionRequests;
    bytes32[] public decreasePositionRequestKeys;

    mapping(address => uint256) public updateCollateralIndex;
    mapping(bytes32 => UpdateCollateralRequest) public updateCollateralRequests;
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

    function storeIncreasePositionRequest(IncreasePositionRequest memory _request)
        public
        onlyFuturXGateway
        returns (uint256, bytes32)
    {
        address account = _request.account;
        uint256 index = increasePositionsIndex[account].add(1);
        increasePositionsIndex[account] = index;
        bytes32 key = _getRequestKey(account, index);

        increasePositionRequests[key] = _request;
        increasePositionRequestKeys.push(key);

        return (index, key);
    }

    function getIncreasePositionRequest(bytes32 _key)
        public
        view
        returns (IncreasePositionRequest memory request)
    {
        request = increasePositionRequests[_key];
    }

    function getDeleteIncreasePositionRequest(bytes32 _key)
        public
        onlyFuturXGateway
        returns (IncreasePositionRequest memory request)
    {
        request = increasePositionRequests[_key];
        Require._require(
            request.account != address(0),
            "FuturXGatewayStorage: 404"
        );
        _deleteIncreasePositionRequests(_key);
    }

    function storeUpdateCollateralRequest(UpdateCollateralRequest memory _request)
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
        returns (UpdateCollateralRequest memory request)
    {
        request = updateCollateralRequests[_key];
        Require._require(
            request.account != address(0),
            "FuturXGatewayStorage: 404"
        );
        _deleteUpdateCollateralRequests(_key);
    }

    function _getRequestKey(address _account, uint256 _index)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_account, _index));
    }

    function _deleteIncreasePositionRequests(bytes32 _key) private {
        delete increasePositionRequests[_key];
    }

    function _deleteUpdateCollateralRequests(bytes32 _key) private {
        delete updateCollateralRequests[_key];
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}
