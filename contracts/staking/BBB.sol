/**
 * @author Musket
 */
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../interfaces/IUniswapV2Router.sol";


contract BBB is OwnableUpgradeable
{



    IUniswapV2Router02 public swapRouter;
    IERC20 public posi;
    address public deadAddress = 0x000000000000000000000000000000000000dEaD;
    uint256 public startEpoch;
    uint256 public endEpoch;
    uint256 public lastTimeBBB;
    uint256 public duration;
    uint256 public amountETH;
    uint256 public amountEthRemaining;
    uint256 public amountETHPerBlock;
    address public weth;


    function initialize(
        IERC20 _posiToken,
        IUniswapV2Router02  _swapRouter
    ) public initializer {
        duration = 3600 * 24 * 7;
        posi = _posiToken;
        swapRouter = _swapRouter;
    }



    function deposit() external payable onlyOwner{

        _bbb(amountEthRemaining);
        amountETH = msg.value;
        amountEthRemaining = msg.value;
        amountETHPerBlock = amountETH / duration;

        startEpoch = block.timestamp;
        endEpoch = block.timestamp + duration;
        lastTimeBBB = block.timestamp;
    }


    function bbb() external {

        require(block.timestamp >= startEpoch, "not started");
        require(block.timestamp <= endEpoch, "ended");

        uint256 timeSinceLastBBB = block.timestamp - lastTimeBBB;
        uint256 amountToBBB = timeSinceLastBBB * amountETHPerBlock;
        amountEthRemaining -= amountToBBB;
        _bbb(amountToBBB);
        lastTimeBBB = block.timestamp;
    }

    function _bbb(uint256 amount) internal {

        uint256[] memory amounts = swapRouter.swapExactETHForTokens{value : amount}(0, _getTokenToPosiRoute(), deadAddress, block.timestamp);
    }

    function _getTokenToPosiRoute()
        private
        view
        returns (address[] memory paths)
    {
        paths = new address[](2);
        paths[0] = weth;
        paths[1] = address(posi);
    }





}
