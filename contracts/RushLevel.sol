// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol"; 
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "contracts/NitroNFT.sol";

contract RushLevel is Ownable{
    using SafeMath for uint256;

    address controller; 
    uint256 REQ_EXP = 300;
    uint256 MAX_LEVEL = 10;
    
    //Leveling System
    struct nftLevel{
        uint256 exp;        //If reaches 300, then level-up and reset to zero
        uint256 level;
    }
    mapping (uint256 => mapping(uint256 => nftLevel)) public nftLevels;
    //^ nftLevels[VaultID][NFTID]

    mapping (uint256 => uint256) public nftLevelRates;
    //^ nftLevelRates[Level][Bonus Rate]


    mapping (uint256 => bool) public Vault;
    //^ Vault[vaultID] = Enable Leveling

    function init(address _controller) public onlyOwner{
        controller = _controller;
        LevelingVault(0, true);     //For Jeepney Rush Leveling
    }     
    function setMaxLevel(uint256 _MAX_LEVEL) public onlyOwner{
        MAX_LEVEL = _MAX_LEVEL;
    }
    function setReqEXP(uint256 _REQ_EXP) public onlyOwner{
        REQ_EXP = _REQ_EXP;
    }

    modifier OnlyController(){
        require(msg.sender==controller,"Only controllers can update");
        _;
    }  
    
    //Owner Functions
    function LevelingVault(uint256 _vaultId, bool _flag) public onlyOwner{
        Vault[_vaultId] = _flag;
    }
 
    //Controller Functions    
    function addExp(uint256 _exp, uint256 _vaultId, uint256 _tokenId) external OnlyController{
        nftLevel memory _nftLevel = nftLevels[_vaultId][_tokenId];
        if (_nftLevel.level > 0){   //Level Exists
            _nftLevel.exp += _exp;
            if (_nftLevel.level>= MAX_LEVEL){
                _nftLevel.exp = 0;
                _nftLevel.level = MAX_LEVEL; 
            }
            else{
                if (_nftLevel.exp > REQ_EXP){
                    _nftLevel.exp = 0;
                    _nftLevel.level++; 
                }
            } 
            nftLevels[_vaultId][_tokenId] = _nftLevel;
        }
        else{
            nftLevels[_vaultId][_tokenId] = nftLevel({
                exp: _exp,
                level: 1
            });
        }
    }
 

    function getNFTLevel(uint256 _vaultId, uint256 _tokenId) public view returns(uint256){
        nftLevel memory _nftLevel = nftLevels[_vaultId][_tokenId];
        return _nftLevel.level;
    }

    function getNFTEXP(uint256 _vaultId, uint256 _tokenId) public view returns(uint256){
        nftLevel memory _nftLevel = nftLevels[_vaultId][_tokenId];
        return _nftLevel.exp;
    }

    function getLevelBonus(uint256 _vaultId, uint256 _tokenId) public view returns(uint256){
        if (Vault[_vaultId]==true){
            nftLevel memory _nftLevel = nftLevels[_vaultId][_tokenId];
            uint256 _level = _nftLevel.level;
            return _level.mul(10).add(100);  
        }
        else{
            return 100;
        }
    }  

}