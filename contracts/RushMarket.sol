// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";  
import "contracts/CrudeOil.sol"; 


contract RushMarket is IERC721Receiver, ReentrancyGuard  {
    using SafeMath for uint256;

    event NFTSell(address owner, ERC721Enumerable nft, uint256 tokenId, IERC20 paymentToken, uint256 value);
    event NFTSellClaim(address owner, ERC721Enumerable nft, uint256 tokenId, IERC20 paymentToken, uint256 value);


    //MarketPlace Variables
    struct collection{
        uint256 totalSale;
    }
    address[] public collections;
    mapping (uint256 => collection) public Collection;
    //^Collection ID

    struct sale{
        address owner;
        address soldBy;
        IERC20 paymentToken;
        uint256 amount;
        bool isStake;
    }
    mapping (uint256 => mapping (uint256 => sale)) public Sale;
    //^Sale[Collection ID][TokenID]


    /*Market Place Functions*/ 
    function _getCollectionId(ERC721Enumerable _nft) private view returns(uint256){
        uint256 colId=0;
        for (uint256 i=0; i<collections.length; i++){
            if(address(_nft) == collections[i]){
                colId = i;
                break;
            }
        }
        return colId;
    }

    function setStake(uint256 colId, uint256 tokenId) public{
        sale memory _sale = Sale[colId][tokenId];
        _sale.isStake = true;
        Sale[colId][tokenId] = _sale;
    }

    function sell(ERC721Enumerable nft, uint256[] calldata tokenIds, IERC20 _paymentToken, uint256 _amount ) external payable nonReentrant {
        uint256 colId = _getCollectionId(nft);
        bool newCol;
        if (colId==0){            
            newCol = true;
            colId = collections.length;
            collections.push(address(nft));
        }

        uint256 tokenId;
        for (uint256 i=0; i<tokenIds.length; i++){
            tokenId = tokenIds[i];

            //Stake While on Sell
            if (nft.ownerOf(tokenId)==address(this)){
                
            }
            else{
                require(nft.ownerOf(tokenId)==msg.sender, "not your token");      
                nft.transferFrom(msg.sender, address(this), tokenId);
            }

            Sale[colId][tokenId] = sale({
                owner: msg.sender,
                soldBy: address(this),
                paymentToken: _paymentToken,
                amount: _amount,
                isStake: false
            });
            emit NFTSell(msg.sender, nft, tokenId, _paymentToken, _amount);
        }
        if (newCol){
            Collection[colId] = collection({ totalSale: tokenIds.length });
        }
        else{
            Collection[colId].totalSale = Collection[colId].totalSale.add(tokenIds.length);
        }
    } 

    function saleDetail(ERC721Enumerable nft, uint256 tokenId) public view returns(sale memory){
        uint256 colId = _getCollectionId(nft);
        return Sale[colId][tokenId];
    }

    function buy(ERC721Enumerable nft, uint256 _tokenId, IERC20 _paymentToken, uint256 value ) external payable nonReentrant {
        uint256 colId = _getCollectionId(nft);
                
        IERC20 paytoken; 
        paytoken = _paymentToken;
        paytoken.approve(address(this), 999999999999999999999999999999 * 1 ether);
        sale memory _Sale = Sale[colId][_tokenId];

        require(_Sale.soldBy==address(this), "Already sold");
        require(_Sale.paymentToken == paytoken, "Invalid Payment Token");
        require(_Sale.amount == value, "Insufficient Payment");
        require(paytoken.balanceOf(msg.sender) >= value * 1 ether, "Not enough balance to complete transaction.");

        paytoken.transferFrom(msg.sender, address(this), value * 1 ether);
        nft.transferFrom(address(this), msg.sender, _tokenId);

        Sale[colId][_tokenId].soldBy = msg.sender;
    }

    function sellClaim(ERC721Enumerable nft, uint256 _tokenId) external payable nonReentrant {
        uint256 colId = _getCollectionId(nft);
        sale memory _Sale = Sale[colId][_tokenId];

        if(_Sale.soldBy != address(this)){
            IERC20 paytoken; 
            paytoken = _Sale.paymentToken;
            paytoken.approve(address(this), 999999999999999999999999999999 * 1 ether);
            paytoken.transferFrom(address(this), msg.sender, _Sale.amount);
            emit NFTSellClaim(msg.sender, nft, _tokenId, _Sale.paymentToken, _Sale.amount);

            delete Sale[colId][_tokenId];
        }
    }
    
    function onERC721Received(
            address,
            address from,
            uint256,
            bytes calldata
        ) external pure override returns (bytes4) {
        require(from == address(0x0), "Cannot send nfts to Vault directly");
        return IERC721Receiver.onERC721Received.selector;
    }
    
}