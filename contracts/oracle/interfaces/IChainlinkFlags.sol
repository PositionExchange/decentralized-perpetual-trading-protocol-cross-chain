pragma solidity ^0.8.9;

interface IChainlinkFlags {
    function getFlag(address) external view returns (bool);
}
