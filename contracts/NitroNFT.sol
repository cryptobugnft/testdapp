// SPDX-License-Identifier: MIT LICENSE

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

pragma solidity ^0.8.0;

contract NitroBoost is ERC721Enumerable, Ownable {
    using EnumerableSet for EnumerableSet.UintSet;
    using Strings for uint256; 

    event Mint(address owner, uint256 tokenId, uint256 value);

    EnumerableSet.UintSet typeIds;

    struct NitroType{ 
        string desc;
        IERC20 paytoken;
        uint256 costvalue;
        string baseURI;
    }
    mapping(uint256 => NitroType) public NitroTypes;
    uint256[] public NitroTypeList;

    uint256 public maxMintAmount = 5;
    bool public paused = false;

    struct nitroToken {
        uint256 tokenId;
        uint256 nitroType;
    }
    mapping(uint256 => nitroToken) public nitroTokens;  

    constructor() ERC721("NitroBoost", "NITRO") {
        AddNitroType("NitroCrude", IERC20(0xf8de182314d89db4b84030c35BaA4116725f79BB), 700, "https://raw.githubusercontent.com/cryptobugnft/nitro/main/tank/1.json");
        AddNitroType("NitroMartinB", IERC20(0xa4ca1691cD9920630B38E08Df6Fb62405dCF3116), 750, "https://raw.githubusercontent.com/cryptobugnft/nitro/main/tank/2.json");
        AddNitroType("NitroKTH", IERC20(0xC5cAFa3Df0e34180eCd0099657C22148dFE117B7), 770, "https://raw.githubusercontent.com/cryptobugnft/nitro/main/tank/3.json");
        AddNitroType("NitroARG", IERC20(0xd6Ef482D601ED2552b45Ecbd47E7c4Ad76b8b014), 770, "https://raw.githubusercontent.com/cryptobugnft/nitro/main/tank/4.json");
        AddNitroType("NitroTango", IERC20(0xCE9F9f44C750e3f995597895700C3449E4d7B915), 800, "https://raw.githubusercontent.com/cryptobugnft/nitro/main/tank/5.json");

        //For Dev Initial Mint
        _mint(1,0);
        _mint(1,1);
        _mint(1,2);
        _mint(1,3);
        _mint(1,4);

    }

    function AddNitroType(
        string memory _desc,
        IERC20 _paytoken,
        uint256 _costvalue,
        string memory _baseURI)public onlyOwner{

        uint256 ctr = NitroTypeList.length;
        NitroTypes[ctr] = NitroType({ 
                desc: _desc,
                paytoken: _paytoken,
                costvalue: _costvalue * 1 ether,
                baseURI: _baseURI
            });
        NitroTypeList.push(ctr);
    }

    function mint(uint256 _mintAmount, uint256 _pid) public payable {
        NitroType storage nitroType = NitroTypes[_pid];

        IERC20 paytoken;
        paytoken = nitroType.paytoken;

        require(_mintAmount > 0);
        require(_mintAmount <= maxMintAmount);

        uint256 cost = nitroType.costvalue;    // * 1 ether;
        //uint256 supply = totalSupply();
        uint256 costval = cost * _mintAmount;
            
        if (msg.sender != owner()) {
            require(paytoken.balanceOf(msg.sender) >= costval, "Not enough balance to complete transaction.");
            require(paytoken.transferFrom(msg.sender, address(this), costval));
        }
         
        _mint(_mintAmount, _pid);

        //Free 1 NFT when maxMint reached
        //supply = totalSupply();
        if (_mintAmount == maxMintAmount){
            _mint(1, _pid);
        }
    }
 
    function walletOfOwner(address _owner) public view returns (uint256[] memory) {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokenIds;
    }

    function getRareType(uint256 _tokenid) public view returns(uint256){
        return _getRareType(_tokenid); 
    }
        
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        return _getTokenRareURI(tokenId);            
    }
    
    function getCryptotoken(uint256 _pid) public view virtual returns(IERC20) {
        NitroType storage nitroType = NitroTypes[_pid];
        IERC20 paytoken;
        paytoken = nitroType.paytoken;
        return paytoken;
    }

    function getNitroPrice(uint256 _pid) public view virtual returns(uint256){
        NitroType storage nitroType = NitroTypes[_pid];
        uint256 costvalue = nitroType.costvalue;
        return costvalue;
    }

    function totalNitroTypes() public view returns(uint256){
        return NitroTypeList.length;
    }
 
    // only owner   
    function updateRarity(uint256[] memory tokenIds, uint256 _nitroType) public onlyOwner{
        for (uint i = 0; i < tokenIds.length; i++){
            nitroTokens[tokenIds[i]].nitroType = _nitroType;             
        }
    }
 
    function setRareURI(uint256 rareId, string memory _uri) public onlyOwner{
        NitroTypes[rareId].baseURI = _uri;
    }
 
    function setmaxMintAmount(uint256 _newmaxMintAmount) public onlyOwner() {
        maxMintAmount = _newmaxMintAmount;
    }

    function setNitroPrice(uint256 _pid, uint256 _costvalue) public onlyOwner{
        NitroTypes[_pid].costvalue = _costvalue * 1 ether;
    }
     
    function pause(bool _state) public onlyOwner() {
        paused = _state;
    }
    
    function withdraw(uint256 _pid) public payable onlyOwner() {
        _withdraw(_pid);
    }

    function withdrawAll() public payable onlyOwner(){
        for (uint256 i=0; i<NitroTypeList.length; i++){
            _withdraw(i);
        }
    }
 
    function _withdraw(uint256 _pid) internal{
        NitroType storage nitroType = NitroTypes[_pid];
        IERC20 paytoken = nitroType.paytoken;
        paytoken.transfer(msg.sender, paytoken.balanceOf(address(this)));
    }

    //Internal Functions
    
    function _mint(uint256 _mintAmount, uint256 _rareId) internal{
        require(paused==false);
        uint256 supply = totalSupply(); 
        for (uint256 i = 1; i <= _mintAmount; i++){ 
            nitroTokens[supply + i] = nitroToken(supply + i, _rareId);     //_rareId for Rarity
            _safeMint(msg.sender, supply + i);
            emit Mint(msg.sender, supply + i, 1);
        }
    }
 
    function _getTokenRareURI(uint256 _tokenid) internal view returns(string memory){
        uint256 _rareId = _getRareType(_tokenid);
        return _getRareURI(_rareId);
    }
    
    function _getRareType(uint256 _tokenid) internal view returns(uint256){
        return nitroTokens[_tokenid].nitroType;
    }

    function _getRareURI(uint256 _nitroType) internal view returns(string memory){
        return NitroTypes[_nitroType].baseURI;
    }


}