pragma solidity ^0.8.2;

interface IChainlinkFlags {
    function getFlag(address) external view returns (bool);
}
