// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/ILpManager.sol";

contract PlpBalance {
    using SafeMath for uint256;

    ILpManager public lpManager;
    address public stakedPlpTracker;

    mapping(address => mapping(address => uint256)) public allowances;

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    constructor(ILpManager _glpManager, address _stakedPlpTracker) public {
        lpManager = _glpManager;
        stakedPlpTracker = _stakedPlpTracker;
    }

    function allowance(
        address _owner,
        address _spender
    ) external view returns (uint256) {
        return allowances[_owner][_spender];
    }

    function approve(
        address _spender,
        uint256 _amount
    ) external returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function transfer(
        address _recipient,
        uint256 _amount
    ) external returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) external returns (bool) {
        uint256 nextAllowance = allowances[_sender][msg.sender].sub(
            _amount,
            "PlpBalance: transfer amount exceeds allowance"
        );
        _approve(_sender, msg.sender, nextAllowance);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    function _approve(
        address _owner,
        address _spender,
        uint256 _amount
    ) private {
        require(
            _owner != address(0),
            "PlpBalance: approve from the zero address"
        );
        require(
            _spender != address(0),
            "PlpBalance: approve to the zero address"
        );

        allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }

    function _transfer(
        address _sender,
        address _recipient,
        uint256 _amount
    ) private {
        require(
            _sender != address(0),
            "PlpBalance: transfer from the zero address"
        );
        require(
            _recipient != address(0),
            "PlpBalance: transfer to the zero address"
        );

        require(
            lpManager.lastAddedAt(_sender).add(lpManager.cooldownDuration()) <=
                block.timestamp,
            "PlpBalance: cooldown duration not yet passed"
        );

        IERC20(stakedPlpTracker).transferFrom(_sender, _recipient, _amount);
    }
}
