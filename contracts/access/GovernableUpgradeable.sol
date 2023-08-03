// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

contract GovernableUpgradeable {
    address public gov;

    event GovChanged(address indexed oldGov, address indexed newGov);

    function __Governable_init() internal {
        gov = msg.sender;
    }

    modifier onlyGov() {
        require(msg.sender == gov, "Governable: forbidden");
        _;
    }

    function setGov(address _gov) external onlyGov {
        emit GovChanged(gov, _gov);
        gov = _gov;
    }
}
