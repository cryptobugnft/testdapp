// SPDX-License-Identifier: MIT LICENSE

pragma solidity 0.8.4;
 
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RushRewarder is Ownable{ 
 
    IERC20 public rewardToken;
    address private operator;
  
    function init(address payable _operator, IERC20 _rewardToken) public payable {
        operator = _operator;
        rewardToken = _rewardToken;
        rewardToken.approve(_operator, rewardToken.totalSupply());
    }

    function transfer(address payable _to, uint256 _amount) external{
        require(msg.sender==operator,"not allowed");
        uint256 balance = rewardToken.balanceOf(address(this));
        require(balance >= _amount);
        
        rewardToken.transfer(_to, _amount);

    }
 
}