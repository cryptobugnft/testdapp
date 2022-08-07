// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "contracts/NitroNFT.sol";
import "contracts/CrudeRewards.sol"; 

contract RushNFTStaking is Ownable, IERC721Receiver {
    using SafeMath for uint256;

    //Events
    event NFTStaked(address owner, ERC721Enumerable nft, uint256 tokenId, uint256 value);
    event NFTUnstaked(address owner, ERC721Enumerable nft, uint256 tokenId, uint256 value);
    event Claimed(address owner, uint256 amount);
    event NFTSell(address owner, ERC721Enumerable nft, uint256 tokenId, IERC20 paymentToken, uint256 value);
    event NFTSellClaim(address owner, ERC721Enumerable nft, uint256 tokenId, IERC20 paymentToken, uint256 value);

    //Global
    uint256 public totalNFTStake;
    uint256 private totalNitroStake;
    uint256 private defaultEmission = 100 ether;
    address private defaultTokenReward;
    NitroBoost private nitroAddress;

    //System
    struct nftstake{
        bool active;
        address owner;
        uint256 timeStamp;        
    }
    mapping (uint256 => mapping (uint256 => nftstake)) public nftStake;
    //^ nftStake[VaultID][TokenID]

    struct nitro{
        uint256 nftId;
        uint256 timeStamp;
        uint256 nitroType;
    }
    uint256[] public nitroStake;
    mapping (uint256 => mapping (uint256 => nitro)) public Nitro;
    //^ Nitro[VaultID][NitroID]

    struct vault{
        uint256 totalStake;     //Live Counter of the Stake
        address nftAddress;     //Contract Address of the NFT 
        address tokenReward;    //Contract Address of the Token Reward
        address delegate;       //Wallet that will distribute the Rewards
        uint256 rewardRate;     //Emission Rate
        string vaultName;       //NFT Description
        bool reqBooster;        //Required Booster
        bool active;
    }
    address[] Vaults;
    mapping (uint256 => vault) public Vault;
    //^ Vault[VaultID]

    struct nitroinfo{
        uint256 power;
        uint256 limit;
        bool active;
    }
    mapping (uint256 => nitroinfo) public nitroInfo;
    //^ nitroInfo[nitroType]

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
    }
    mapping (uint256 => mapping (uint256 => sale)) public Sale;
    //^Collection ID => Token ID => sale

    constructor(
        NitroBoost NitroAddress,
        address VaultAddress,
        address TokenRewardAddress,
        uint256 RewardRate        
    ){
        	
        //JeepneyRush Vault
        AddVault(VaultAddress, TokenRewardAddress, address(this), RewardRate, false);
        
        //Set Nitro Address;
        nitroAddress = NitroAddress;

        //Set Default Token Reward Address;
        defaultTokenReward = TokenRewardAddress;

        //Add 2 Nitro Types;
        //1 DAY == 86400
        AddNitroInfo(0, 125, 259200);   //"Common"      >> 1.25 => 125 * 1 / 100     -> 3 DAYS
        AddNitroInfo(1, 210, 864000);   //"Rare"        >> 2.10 => 210 * 1 / 100    ->  10 DAYS

    }

    //Owner Functions
    //To Claim JeepneyRush rewards
    function withdraw() public payable onlyOwner {
        (bool success, ) = payable(msg.sender).call{value: address(this).balance}("");
        require(success);
    }

    function setDefEmission(uint256 _rate) public onlyOwner{
        defaultEmission = _rate* 1 ether;     //Convert to ether
    }

    function getNitroAddress() public view returns(address){
        return address(nitroAddress);
    }
    function setNitroAddress(NitroBoost _nitroAddress) public onlyOwner{
        nitroAddress = _nitroAddress;
    }

    function AddNitroInfo(
        uint256 _nitroTypeId,
        uint256 _power,
        uint256 _limit
    ) public onlyOwner{
        nitroInfo[_nitroTypeId] = nitroinfo({
            power: _power,
            limit: _limit,
            active: true
        });               
    }
    function DisableNitroInfo(uint256 _nitroTypeId) public onlyOwner{
        nitroInfo[_nitroTypeId].active=false;
    }

    function AddVault(
        address _nftAddress,
        address _tokenReward,
        address _delegate,
        uint256 _rewardRate,
        bool _reqBooster
    ) public onlyOwner{        
        ERC721Enumerable nft;
        nft = ERC721Enumerable(_nftAddress);

        Vault[Vaults.length] = vault({
            totalStake: 0,
            nftAddress: _nftAddress,
            tokenReward: _tokenReward,
            delegate: _delegate,
            rewardRate: _rewardRate,
            vaultName: nft.name(),
            reqBooster: _reqBooster,
            active: true

        });
        Vaults.push(_nftAddress);
    }
    function DisableVault(uint256 vaultId) public onlyOwner{
        Vault[vaultId].active=false;
    }

    function CheckOwner(ERC721Enumerable nft, uint256 tokenId) public view returns(bool){
        return nft.ownerOf(tokenId) == msg.sender;
    }

    function getVaultId(address nft) public view returns(uint256){
        return _getVaultId(nft);
    }

    function _generateVaultId() private view returns(uint256){
        return Vaults.length;
    }

    //Public Functions
    function stakeAny(ERC721Enumerable nft, uint256[] calldata tokenIds) external payable{
        uint256 tokenId;

        address _nftAddr = address(nft);
        uint256 vaultId = getVaultId(_nftAddr);
        if (vaultId == 0){
            if (_nftAddr != Vault[vaultId].nftAddress){
                vaultId = _generateVaultId();
                AddVault(_nftAddr, defaultTokenReward, address(this), defaultEmission, true);
            }
        } 
 
        for (uint256 i=0; i<tokenIds.length; i++){
            tokenId = tokenIds[i];

            require(nft.ownerOf(tokenId) == msg.sender, "not your token");

            nft.transferFrom(msg.sender, address(this), tokenId);
            nftStake[vaultId][tokenId] = nftstake({                
                active: true,
                owner: msg.sender,
                timeStamp: uint256(block.timestamp)
            });

            emit NFTStaked(msg.sender, nft, tokenId, block.timestamp);
        }
        Vault[vaultId].totalStake = Vault[vaultId].totalStake.add(tokenIds.length);
        totalNFTStake = totalNFTStake.add(tokenIds.length);
    }

    function stake(uint256 vaultId, uint256[] calldata tokenIds) external payable{
        uint256 tokenId;
        address _nftAddr = _getVaultAddress(vaultId);
        ERC721Enumerable nft = ERC721Enumerable(_nftAddr);
 
        for (uint256 i=0; i<tokenIds.length; i++){
            tokenId = tokenIds[i];

            require(nft.ownerOf(tokenId) == msg.sender, "not your token");

            nft.transferFrom(msg.sender, address(this), tokenId);
            nftStake[vaultId][tokenId] = nftstake({                
                active: true,
                owner: msg.sender,
                timeStamp: uint256(block.timestamp)
            });

            emit NFTStaked(msg.sender, nft, tokenId, block.timestamp);
        }
        Vault[vaultId].totalStake = Vault[vaultId].totalStake.add(tokenIds.length);
        totalNFTStake = totalNFTStake.add(tokenIds.length);
    }

    function claim(uint256 vaultId, uint256[] calldata tokenIds) external payable {
        _claim(msg.sender, vaultId, tokenIds, false);
    }

    function claimForAddress(uint256 vaultId, address _account, uint256[] calldata tokenIds) external {
        _claim(_account, vaultId, tokenIds, false);
    }

    function unstake(uint256 vaultId, uint256[] calldata tokenIds) external payable {
        _claim(msg.sender, vaultId, tokenIds, true);
    }

    function pendingReward(uint256 vaultId, uint256 tokenId) public view returns(uint256){
        return _pendingReward(vaultId, msg.sender, tokenId);
    }
    
    function getTokenPowerUp(uint256 vaultId, uint256 tokenId) public view returns(uint256){
        return _getTokenPowerUp(vaultId, tokenId);
    }

    function stakeNitro(uint256 vaultId, uint256 tokenId, uint256 nitroId) external payable{
        require(nitroAddress.ownerOf(nitroId) == msg.sender, "not your token");
        nitroAddress.transferFrom(msg.sender, address(this), nitroId);

        Nitro[vaultId][nitroId] = nitro({
            nftId: tokenId,
            timeStamp: uint256(block.timestamp),
            nitroType: nitroAddress.getRareType(nitroId)
        });

        //Reset Stake Time
        nftStake[vaultId][tokenId].timeStamp = Nitro[vaultId][nitroId].timeStamp;

        nitroStake.push(nitroId);
    }
    
    function stakeTime(uint256 vaultId, uint256 tokenId) public view returns(uint256){
        return _stakeTime(vaultId, tokenId);
    }


    //Private Functions
    function _claim(address account, uint256 vaultId, uint256[] calldata tokenIds, bool _unstake) internal{
        uint256 earned = 0; 
        uint256 fixTimeStamp = uint256(block.timestamp);

        uint256 tokenId;
        for (uint256 i=0; i<tokenIds.length; i++){
            tokenId = tokenIds[i];
            earned = earned.add(_pendingReward(vaultId, account, tokenId));                                     
            nftStake[vaultId][tokenId].timeStamp = fixTimeStamp;                        
        }
        if (earned > 0){
            //Default distribution of rewards is the minting function.
            //Once the tokenrewards supply reached its maximum, it will call the transfer
            //Dev Note: Make sure theres enough fund on the staking vault address

            TokenRewards _TokenRewards = TokenRewards(Vault[vaultId].tokenReward);
            if(_TokenRewards.totalSupply().add(earned) <= _TokenRewards.maxSupply()){
                _TokenRewards.mint(account, earned);
            }
            else{ 
                address _delegate = Vault[vaultId].delegate;
                require(_TokenRewards.balanceOf(_delegate) >= earned, "Vault has insuficient fund");
                _TokenRewards.transferFrom(_delegate, account, earned);
            }
        }

        if (_unstake) {
            _unstakeMany(vaultId, tokenIds);
        }
        emit Claimed(account, earned);

    }

    function _unstakeMany(uint256 vaultId, uint256[] calldata tokenIds) internal{
        uint256 tokenId;
        ERC721Enumerable nft;
        nft = ERC721Enumerable(_getVaultAddress(vaultId));

        for (uint256 i=0; i<tokenIds.length; i++){
            tokenId = tokenIds[i];
            require(nftStake[vaultId][tokenId].owner==msg.sender, "Not the owner");
            
            nft.transferFrom(address(this), msg.sender, tokenId);

            delete nftStake[vaultId][tokenId];
        }

        Vault[vaultId].totalStake = Vault[vaultId].totalStake.sub(tokenIds.length);
        totalNFTStake = totalNFTStake.sub(tokenIds.length);

        emit NFTUnstaked(msg.sender, nft, tokenId, block.timestamp);
    }

    function _stakeTime(uint256 vaultId, uint256 tokenId) private view returns(uint256){
        nftstake memory _nftStake = nftStake[vaultId][tokenId];
        return block.timestamp.sub(_nftStake.timeStamp);       

    }

    function _pendingReward(uint256 vaultId, address account, uint256 tokenId) private view returns(uint256){
        uint256 reward;
        nftstake memory _nftStake = nftStake[vaultId][tokenId];

        uint256 rewardRate = defaultEmission;
        if ((Vault[vaultId].active==true) && (Vault[vaultId].reqBooster==false)){
            rewardRate = Vault[vaultId].rewardRate * 1 ether;
        }

        uint256 NFTstakeTime;

        require(_nftStake.owner==account, "Not the owner");
        require(_nftStake.active==true, "Staking not active");

        NFTstakeTime = _stakeTime(vaultId, tokenId);
        reward = NFTstakeTime.mul(rewardRate).div(86400);

        uint256 powerUp = _getTokenPowerUp(vaultId, tokenId);
        if (powerUp>1){
            reward = reward.mul(powerUp.div(100));
        }

        reward = reward.div(100);

        //For StakeAny NFT, if Booster is not staked/bind in the NFT, no reward generated
        if (Vault[vaultId].reqBooster && powerUp==0){
            reward = 0;
        }

        return reward;
    }
    
    function nitroStakeTime(uint256 vaultId, uint256 nitroId) public view returns(uint256){
        nitro memory _Nitro = Nitro[vaultId][nitroId];
        return block.timestamp.sub(_Nitro.timeStamp);
    }

    function _getTokenPowerUp(uint256 vaultId, uint256 tokenId) private view returns(uint256){
        uint256 powerUp=0;
        uint256 nitroId=0;

        nitro memory _Nitro;
        nitroinfo memory _nitroInfo;

        uint256 NFTstakeTime;
        for (uint256 i=0; i<nitroStake.length; i++){
            nitroId = nitroStake[i];
            _Nitro = Nitro[vaultId][nitroId];
            _nitroInfo = nitroInfo[_Nitro.nitroType];

            if (_nitroInfo.active) {                
                if (_Nitro.nftId == tokenId){
                    NFTstakeTime = nitroStakeTime(vaultId, nitroId).div(86400); //block.timestamp.sub(_Nitro.timeStamp).div(86400);
                    if (_nitroInfo.limit >= NFTstakeTime){
                        powerUp = powerUp.add(_nitroInfo.power);
                    }
                }
            }
        }
        return powerUp;
    }
 
    function _getVaultAddress(uint256 vaultId) private view returns(address){
        return Vault[vaultId].nftAddress;
    }

    function _getVaultId(address nft) private view returns(uint256){
        uint256 _vaultId=0;
        for (uint256 i=0; i<Vaults.length; i++){
            if (Vaults[i]==nft){
                _vaultId = i;
                break;
            }
        }
        return _vaultId;
    }

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

    function sell(ERC721Enumerable nft, uint256[] calldata tokenIds, IERC20 _paymentToken, uint256 _amount ) external payable{
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
            require(nft.ownerOf(tokenId)==msg.sender, "not your token");

            nft.transferFrom(msg.sender, address(this), tokenId);
            Sale[colId][tokenId] = sale({
                owner: msg.sender,
                soldBy: address(this),
                paymentToken: _paymentToken,
                amount: _amount
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

    function buy(ERC721Enumerable nft, uint256 _tokenId, IERC20 _paymentToken, uint256 value ) external payable{
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

    function sellClaim(ERC721Enumerable nft, uint256 _tokenId) external payable{
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