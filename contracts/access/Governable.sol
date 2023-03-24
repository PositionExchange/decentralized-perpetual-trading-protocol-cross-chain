// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

contract Governable {
    address public gov;

    event GovChanged(address indexed oldGov, address indexed newGov);

    constructor() {
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