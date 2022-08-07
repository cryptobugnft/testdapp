// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "contracts/NitroNFT.sol";
import "contracts/CrudeOil.sol"; 
import "contracts/RushMarket.sol";
import "contracts/RushRewarder.sol";
import "contracts/RushLevel.sol";

contract RushNFTStaking is Ownable, IERC721Receiver {
    using SafeMath for uint256;
  
    //Events
    event NFTStaked(address owner, ERC721Enumerable nft, uint256 tokenId, uint256 value);
    event NFTUnstaked(address owner, ERC721Enumerable nft, uint256 tokenId, uint256 value);
    event Claimed(address owner, uint256 amount);
    event NFTLevelUp(ERC721Enumerable nft, uint256 tokenId, uint256 level);
    event EquippedNitro(uint256 vaultId, uint256 tokenId, uint256 nitroId, uint256 nitroStakeTime);

    //Global
    uint256 public totalNFTStake;
    uint256 private totalNitroStake;
    uint256 private defaultEmission = 25 ether;
    address private defaultTokenReward;

    NitroBoost private nitroBooster;
    RushLevel private rushLevel;
    RushMarket private rushMarket;

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
        uint256 totalStake;             //Live Counter of the Stake
        address nftAddress;             //Contract Address of the NFT 
        address tokenReward;            //Contract Address of the Token Reward
        address payable delegate;       //Wallet that will distribute the Rewards
        uint256 rewardRate;             //Emission Rate
        string vaultName;               //NFT Description
        bool reqBooster;                //Required Booster
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


    constructor(
        address _nitroAddress,
        address VaultAddress,
        address TokenRewardAddress,
        uint256 RewardRate,
        address _rushMarket,
        address _rushLevel
    ){
        setNitroBoost(_nitroAddress); 
        setLevelAddress(_rushLevel);
        setMarketAddress(_rushMarket);
        	
        //JeepneyRush Vault
        _AddVault(VaultAddress, TokenRewardAddress, address(this), RewardRate, false);
          
        //Set Default Token Reward Address;
        defaultTokenReward = TokenRewardAddress;

        //Add 2 Nitro Types;
        //1 DAY == 86400
        AddNitroInfo(0, 200, 86400 * 7);   //"CrudeOil Mint"        >> 2.00 => 200 * 1 / 100     -> 7 DAYS
        AddNitroInfo(1, 210, 86400 * 7);   //"MartinB Mint"         >> 2.10 => 210 * 1 / 100    ->  7 DAYS
        AddNitroInfo(2, 220, 86400 * 7);   //"KTH Mint"             >> 2.20 => 220 * 1 / 100    ->  7 DAYS
        AddNitroInfo(3, 220, 86400 * 7);   //"ARG Mint"             >> 2.20 => 220 * 1 / 100    ->  7 DAYS
        AddNitroInfo(4, 230, 86400 * 7);   //"Tango Mint"           >> 2.30 => 230 * 1 / 100    ->  7 DAYS 
        
    }

    //Owner Functions
    function setMarketAddress(address _rushMarket) public onlyOwner{
        rushMarket = RushMarket(_rushMarket);    
    }

    function setLevelAddress(address _rushLevel) public onlyOwner{ 
        rushLevel = RushLevel(_rushLevel);
    }

    //To Claim JeepneyRush rewards
    function withdraw() public payable onlyOwner {
        (bool success, ) = payable(msg.sender).call{value: address(this).balance}("");
        require(success);
    }

    function setDefEmission(uint256 _rate) public onlyOwner{
        defaultEmission = _rate* 1 ether;     //Convert to ether
    }

    function getNitroAddress() public view returns(address){
        return address(nitroBooster);
    }
    function setNitroBoost(address _nitroAddress) public onlyOwner{
        nitroBooster = NitroBoost(_nitroAddress);
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
        nitroinfo memory _nitroinfo = nitroInfo[_nitroTypeId];
        _nitroinfo.active=false;
        nitroInfo[_nitroTypeId] = _nitroinfo;
    }

    function AddVault(
        address _nftAddress,
        address _tokenReward,
        address _delegate,
        uint256 _rewardRate,
        bool _reqBooster
    ) public onlyOwner{  
        _AddVault(_nftAddress, _tokenReward, _delegate, _rewardRate, _reqBooster);
    }

    function DisableVault(uint256 vaultId) public onlyOwner{
        vault memory _vault = Vault[vaultId];
        _vault.active=false;
        Vault[vaultId] = _vault;
    }

    function UpdateVaultRate(uint256 _vaultId, uint256 _rewardRate) public onlyOwner{
        _UpdateVaultRate(_vaultId, _rewardRate);
    }

    function VaultBooster(uint256 _vaultId, bool _reqBooster) public onlyOwner{
        _VaultBooster(_vaultId, _reqBooster);
    }

    function UpdateVaultDelegate(uint256 _vaultId, address _delegate) public onlyOwner{
        _UpdateVaultDelegate(_vaultId, _delegate);
    }

    function getVaultId(address nft) public view returns(uint256){
        return _getVaultId(nft);
    }

    function _generateVaultId() private view returns(uint256){
        return Vaults.length;
    }

    //Public Functions 
    function stakeAny(ERC721Enumerable nft, uint256[] calldata tokenIds, bool notOnSale) external payable{
        uint256 tokenId;

        address _nftAddr = address(nft);
        uint256 vaultId = getVaultId(_nftAddr);
        if (vaultId == 0){
            if (_nftAddr != Vault[vaultId].nftAddress){
                vaultId = _generateVaultId();
                _AddVault(_nftAddr, defaultTokenReward, address(this), defaultEmission, true);
            }
        } 
 
        for (uint256 i=0; i<tokenIds.length; i++){
            tokenId = tokenIds[i];

            if (notOnSale==false){
                require(nft.ownerOf(tokenId) == address(rushMarket), "not your token");
                RushMarket _rushMarket = RushMarket(address(rushMarket));
                _rushMarket.setStake(vaultId, tokenId);
            }
            else{
                require(nft.ownerOf(tokenId) == msg.sender, "not your token");
                nft.transferFrom(msg.sender, address(this), tokenId);
            }

            nftStake[vaultId][tokenId] = nftstake({                
                active: true,
                owner: msg.sender,
                timeStamp: uint256(block.timestamp)
            });

            emit NFTStaked(msg.sender, nft, tokenId, block.timestamp);
        }
        updateVaultStake(vaultId, tokenIds.length);
        totalNFTStake = totalNFTStake.add(tokenIds.length);
    }

    function updateVaultStake(uint256 vaultId, uint256 _amount) private{
        vault memory _vault = Vault[vaultId];
        _vault.totalStake = _vault.totalStake.add(_amount);
        Vault[vaultId] = _vault;
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
        updateVaultStake(vaultId, tokenIds.length);
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

    function pendingRewardByAccount(uint256 vaultId, address account) public view returns(uint256){
        return _pendingRewardByAccount(vaultId, account);
    }

    function pendingReward(uint256 vaultId, uint256 tokenId) public view returns(uint256){
        return _pendingReward(vaultId, /*msg.sender,*/ tokenId);
    }
    
    function getTokenPowerUp(uint256 vaultId, uint256 tokenId) public view returns(uint256){
        return _getTokenPowerUp(vaultId, tokenId);
    }

    function stakeNitro(uint256 vaultId, uint256 tokenId, uint256 nitroId) external payable{
        require(_getTokenPowerUp(vaultId, tokenId)<=1, "wait til current nitro expired"); 
        require(nitroBooster.ownerOf(nitroId) == msg.sender, "not your token");

        uint256 nitroStakeTime = uint256(block.timestamp);

        Nitro[vaultId][nitroId] = nitro({
            nftId: tokenId,
            timeStamp: nitroStakeTime,
            nitroType: nitroBooster.getRareType(nitroId)
        });

        //Reset Stake Time
        nftStake[vaultId][tokenId].timeStamp = nitroStakeTime;

        nitroStake.push(nitroId);

        //NFT Level        
        uint256 _power = getNitroPower(vaultId, nitroId);
        RushLevel _rushLevel = RushLevel(address(rushLevel));
        _rushLevel.addExp(_power, vaultId, tokenId);

        nitroBooster.transferFrom(msg.sender, address(this), nitroId);
        emit EquippedNitro(vaultId, tokenId, nitroId, nitroStakeTime);
    }

    function getNitroPower(uint256 vaultId, uint256 nitroId) public view returns(uint256){
        uint256 _nitroType = Nitro[vaultId][nitroId].nitroType;
        return nitroInfo[_nitroType].power;
    }
    
    function stakeTime(uint256 vaultId, uint256 tokenId) public view returns(uint256){
        return _stakeTime(vaultId, tokenId);
    }


    //Private Functions
    function _UpdateVaultRate(uint256 _vaultId, uint256 _rewardRate) internal{
        vault memory _vault = Vault[_vaultId];
        _vault.rewardRate = _rewardRate * 1 ether;
        Vault[_vaultId] = _vault;   //.rewardRate = _rewardRate * 1 ether;
    }

    function _VaultBooster(uint256 _vaultId, bool _reqBooster) internal{
        vault memory _vault = Vault[_vaultId];
        _vault.reqBooster = _reqBooster;
        Vault[_vaultId] = _vault;
    }

    function _UpdateVaultDelegate(uint256 _vaultId, address _delegate) internal{
        vault memory _vault = Vault[_vaultId];
        _vault.delegate = payable(_delegate);
        Vault[_vaultId] = _vault;
    }

    function _AddVault(
        address _nftAddress,
        address _tokenReward,
        address _delegate,
        uint256 _rewardRate,
        bool _reqBooster
    ) internal{        
        ERC721Enumerable nft;
        nft = ERC721Enumerable(_nftAddress);
        
        uint256 _rate = _rewardRate * 1 ether;
        if(_reqBooster){
            _rate = _rewardRate;                
        }

        Vault[Vaults.length] = vault({
            totalStake: 0,
            nftAddress: _nftAddress,
            tokenReward: _tokenReward,
            delegate: payable(_delegate),
            rewardRate: _rate,
            vaultName: nft.name(),
            reqBooster: _reqBooster,
            active: true
        });
        Vaults.push(_nftAddress);
    }

    function _claim(address account, uint256 vaultId, uint256[] calldata tokenIds, bool _unstake) internal{
        uint256 earned = 0; 
        uint256 fixTimeStamp = uint256(block.timestamp);
        uint256 tokenId;

        for (uint256 i=0; i<tokenIds.length; i++){
            tokenId = tokenIds[i];
            earned = earned.add(_pendingReward(vaultId, tokenId));                                     
            nftStake[vaultId][tokenId].timeStamp = fixTimeStamp;   
                
            //Clean Expired Equipped Nitro
            _cleanEquippedNitro(vaultId, tokenId);                     
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
                RushRewarder rewarder = RushRewarder(Vault[vaultId].delegate);
                rewarder.transfer(payable(account), earned);
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

    function _pendingRewardByAccount(uint256 vaultId, address account) private view returns(uint256){
        uint256 _pendReward;

        ERC721Enumerable nft = ERC721Enumerable(_getVaultAddress(vaultId));
        uint256 _tokenReward;
        for (uint256 i=0; i<Vault[vaultId].totalStake; i++){
            uint256 _tokenId = nft.tokenOfOwnerByIndex(address(this), i);

            if (nftStake[vaultId][_tokenId].owner == account ){
                _tokenReward = _pendingReward(vaultId, _tokenId);
                _pendReward = _pendReward + _tokenReward;
            }
            
        }
        return _pendReward;
    }

    function _pendingReward(uint256 vaultId, uint256 tokenId) private view returns(uint256){
        uint256 reward;
        uint256 rewardRate = defaultEmission;

        vault memory _vault = Vault[vaultId];

        if ((_vault.active==true) && (_vault.reqBooster==false)){
            rewardRate = _vault.rewardRate; 
        }

        uint256 NFTstakeTime = _stakeTime(vaultId, tokenId);
        reward = NFTstakeTime.mul(rewardRate).div(86400);

        uint256 powerUp = _getTokenPowerUp(vaultId, tokenId); 
        uint256 levelBonus = rushLevel.getLevelBonus(vaultId, tokenId).div(100);
        powerUp = powerUp.mul(levelBonus); //Level Bonus Rate

        if (powerUp>1){
            reward = reward.mul(powerUp.div(100));
        }
        else if (powerUp==1){       //For Expired Nitro Equipped
            reward = _getNitroPowerValue(vaultId, tokenId);
        }
 
        //For StakeAny NFT, if Booster is not staked/bind in the NFT, no reward generated
        if (_vault.reqBooster && powerUp==0){
            reward = 0;
        }

        return reward;
    }
    
    /* Additional NitroNFT functions*/
    function getEquippedNitro(uint256 vaultId, uint256 tokenId) public view returns(uint256){
        return _getEquippedNitro(vaultId, tokenId);
    }
    function getNitroActive(uint256 vaultId, uint256 nitroId) public view returns(bool){
        return _getNitroActive(vaultId, nitroId);
    }
    function nitroStakedTime(uint256 vaultId, uint256 nitroId) public view returns(uint256){
        return _nitroStakedTime(vaultId, nitroId);
    }
    function nitroStakeRemaining(uint256 vaultId, uint256 tokenId) public view returns(uint256 nitroId, uint256 limit, uint256 remain){
        (nitroId, limit, remain) = _nitroStakeRemaining(vaultId, tokenId);
    }


    function _nitroStakedTime(uint256 vaultId, uint256 nitroId) private view returns(uint256 _nitroTime){
        nitro memory _Nitro = Nitro[vaultId][nitroId];
        if (_Nitro.timeStamp>0){
            _nitroTime = block.timestamp.sub(_Nitro.timeStamp);
        }
    }

    function _getEquippedNitro(uint256 vaultId, uint256 tokenId) private view returns(uint256 _nitroId){
        nitro memory _Nitro;
        for (uint256 i=0; i<nitroStake.length; i++){
            _Nitro = Nitro[vaultId][nitroStake[i]];
            if ((_Nitro.nftId == tokenId) && (nitroInfo[_Nitro.nitroType].active)){
                _nitroId = nitroStake[i];
                break;
            }
        }
    }

    function _getNitroActive(uint256 vaultId, uint256 nitroId) private view returns(bool){
        nitro memory _Nitro = Nitro[vaultId][nitroId];
        nitroinfo memory _nitroInfo = nitroInfo[_Nitro.nitroType];
        return _nitroInfo.active;
    }

    function _getNitroLimit(uint256 vaultId, uint256 nitroId) private view returns(uint256){
        nitro memory _Nitro = Nitro[vaultId][nitroId];
        nitroinfo memory _nitroInfo = nitroInfo[_Nitro.nitroType];
        return _nitroInfo.limit;
    }

    function _nitroStakeRemaining(uint256 vaultId, uint256 tokenId) private view returns(uint256 nitroId, uint256 limit, uint256 remain){
        //uint256 _res = 0;
        nitroId = _getEquippedNitro(vaultId, tokenId);
        if (nitroId > 0){
            uint256 nitroStakeTime = _nitroStakedTime(vaultId, nitroId);
            limit = _getNitroLimit(vaultId, nitroId);
            if (nitroStakeTime < limit){
                remain = limit - nitroStakeTime;
            }
            else{
                remain=0;
            }
        }
    }

    //Only for Expired Equipped Nitro 
    function _getNitroPowerValue(uint256 vaultId, uint256 tokenId) private view returns(uint256){
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
                    NFTstakeTime = nitroStakedTime(vaultId, nitroId).div(86400); //block.timestamp.sub(_Nitro.timeStamp).div(86400);
                    if(NFTstakeTime > _nitroInfo.limit){       //Nitro Equip expired
                        powerUp = _nitroInfo.power;
                    }
                }
            }
        }
        return powerUp;
    }

    uint256[] private del_nitro;

    function _cleanEquippedNitro(uint256 vaultId, uint256 tokenId) internal{
        uint256 nitroId=0;
        uint256 NFTstakeTime;
        for (uint256 i=0; i<nitroStake.length; i++){
            nitroId = nitroStake[i];
            (bool _active, uint256 _nftId, uint256 _limit, uint256 _power) = getNitroInfo(vaultId, nitroId);
            _power = 0; //unused variable

            if (_active) {                
                if (_nftId == tokenId){
                    NFTstakeTime = nitroStakedTime(vaultId, nitroId).div(86400);  
                    if(NFTstakeTime > _limit){       //Nitro Equip expired 
                        del_nitro.push(nitroId);
                    }
                }
            }
        } 
        for (uint256 i=0; i<del_nitro.length;i++){
            uint256 _nitroId = del_nitro[i];
            delete Nitro[vaultId][_nitroId];
        }
    }

    function _getTokenPowerUp(uint256 vaultId, uint256 tokenId) private view returns(uint256){
        uint256 powerUp=0;
        uint256 nitroId=0;
        uint256 NFTstakeTime;

        for (uint256 i=0; i<nitroStake.length; i++){
            nitroId = nitroStake[i];
            (bool _active, uint256 _nftId, uint256 _limit, uint256 _power) = getNitroInfo(vaultId, nitroStake[i]);

            if (_active) {                
                if (_nftId == tokenId){
                    NFTstakeTime = nitroStakedTime(vaultId, nitroId).div(86400); 
                    if (_limit >= NFTstakeTime){
                        powerUp = powerUp.add(_power);
                    }
                    else if(NFTstakeTime > _limit){       //Nitro Equip expired set to 1
                        powerUp = 1;
                    }
                }
            }
        }
        return powerUp;
    }

    function getNitroInfo(uint256 vaultId, uint256 nitroId) public view returns(bool active, uint256 nftId, uint256 limit, uint256 power){
        nitro memory _Nitro = Nitro[vaultId][nitroId];
        nitroinfo memory _nitroInfo = nitroInfo[_Nitro.nitroType];

        active = _nitroInfo.active;
        nftId = _Nitro.nftId;
        limit = _nitroInfo.limit;
        power = _nitroInfo.power;
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