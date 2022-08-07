// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "contracts/NitroNFT.sol";
import "contracts/CrudeRewards.sol"; 

contract NFTStaking is Ownable, IERC721Receiver {
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
    uint256[] nitroStake;
    mapping (uint256 => mapping (uint256 => nitro)) public Nitro;
    //^ Nitro[VaultID][NitroID]

    struct vault{
        uint256 totalStake;     //Live Counter of the Stake
        address nftAddress;     //Contract Address of the NFT 
        address tokenReward;    //Contract Address of the Token Reward
        address delegate;       //Wallet that will distribute the Rewards
        uint256 rewardRate;     //Emission Rate
        string vaultName;       //NFT Description
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
        NitroBoost NitroAddress,
        address VaultAddress,
        address TokenRewardAddress,
        uint256 RewardRate
    ){
        //JeepneyRush Vault
        AddVault(VaultAddress, TokenRewardAddress, address(this), RewardRate*10**18);

        //Set Nitro Address;
        nitroAddress = NitroAddress;

        //Add 2 Nitro Types;
        //1 DAY == 86400
        AddNitroInfo(1, 125, 259200);   //"Common"      >> 1.25 => 125 * 1 / 100     -> 3 DAYS
        AddNitroInfo(2, 210, 864000);   //"Rare"        >> 2.10 => 210 * 1 / 100    ->  10 DAYS

    }

    //Owner Functions
    //To Claim JeepneyRush rewards
    function withdraw() public payable onlyOwner {
        (bool success, ) = payable(msg.sender).call{value: address(this).balance}("");
        require(success);
    }

    function setDefEmission(uint256 _rate) public onlyOwner{
        defaultEmission = _rate*10**18;     //Convert to ether
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
        uint256 _rewardRate
    ) public onlyOwner{        
        ERC721Enumerable nft;
        nft = ERC721Enumerable(_nftAddress);

        Vault[Vaults.length] = vault({
            totalStake: 0,
            nftAddress: _nftAddress,
            tokenReward: _tokenReward,
            delegate: _delegate,
            rewardRate: _rewardRate*10**18,
            vaultName: nft.name(),
            active: true

        });
        Vaults.push(_nftAddress);
    }
    function DisableVault(uint256 vaultId) public onlyOwner{
        Vault[vaultId].active=false;
    }

    //Public Functions
    function stake(uint256 vaultId, uint256[] calldata tokenIds) external payable{
        uint256 tokenId;
        ERC721Enumerable nft;
        nft = ERC721Enumerable(_getVaultAddress(vaultId));
 
        for (uint256 i=0; i<tokenIds.length; unsafe_inc(i)){
            tokenId = tokenIds[i];

            require(nft.ownerOf(tokenId)==address(this),"Already staked");
             
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

    function claim(uint256 vaultId, uint256[] calldata tokenIds) external {
        _claim(msg.sender, vaultId, tokenIds, false);
    }

    function claimForAddress(uint256 vaultId, address _account, uint256[] calldata tokenIds) external {
        _claim(_account, vaultId, tokenIds, false);
    }

    function unstake(uint256 vaultId, uint256[] calldata tokenIds) external {
        _claim(msg.sender, vaultId, tokenIds, true);
    }

    function pendingReward(uint256 vaultId, address account, uint256 tokenId) public view returns(uint256){
        return _pendingReward(vaultId, account, tokenId);
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
        nitroStake.push(nitroId);
    }

    //Private Functions
    function _claim(address account, uint256 vaultId, uint256[] calldata tokenIds, bool _unstake) internal{
        uint256 earned = 0; 
        uint256 fixTimeStamp = uint256(block.timestamp);

        uint256 tokenId;
        for (uint256 i=0; i<tokenIds.length; unsafe_inc(i)){
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

        for (uint256 i=0; i<tokenIds.length; unsafe_inc(i)){
            tokenId = tokenIds[i];
            require(nftStake[vaultId][tokenId].owner==msg.sender, "Not the owner");
            
            nft.transferFrom(address(this), msg.sender, tokenId);

            delete nftStake[vaultId][tokenId];
        }

        Vault[vaultId].totalStake = Vault[vaultId].totalStake.sub(tokenIds.length);
        totalNFTStake = totalNFTStake.sub(tokenIds.length);

        emit NFTUnstaked(msg.sender, nft, tokenId, block.timestamp);
    }

    function _pendingReward(uint256 vaultId, address account, uint256 tokenId) private view returns(uint256){
        uint256 reward;
        nftstake memory _nftStake = nftStake[vaultId][tokenId];

        uint256 rewardRate = defaultEmission;
        if (Vault[vaultId].active){
            rewardRate = Vault[vaultId].rewardRate;
        }

        uint256 stakeTime;

        require(_nftStake.owner==account, "Not the owner");
        require(_nftStake.active==true, "Staking not active");

        stakeTime = block.timestamp.sub(_nftStake.timeStamp).div(86400);       
        reward = stakeTime.mul(rewardRate.div(100));
        
        uint256 powerUp = _getTokenPowerUp(vaultId, tokenId);
        if (powerUp>1){
            reward = reward.mul(powerUp);
        }

        return reward;
    }
    
    function _getTokenPowerUp(uint256 vaultId, uint256 tokenId) private view returns(uint256){
        uint256 powerUp=0;
        uint256 nitroId=0;

        nitro memory _Nitro;
        nitroinfo memory _nitroInfo = nitroInfo[_Nitro.nitroType];

        uint256 stakeTime;
        for (uint256 i=0; i<nitroStake.length; unsafe_inc(i)){
            if (_nitroInfo.active) {
                nitroId = nitroStake[i];
                _Nitro = Nitro[vaultId][nitroId];
                
                if (_Nitro.nftId == tokenId){
                    stakeTime = block.timestamp.sub(_Nitro.timeStamp).div(86400);
                    if (_nitroInfo.limit >= stakeTime){
                        powerUp = powerUp.add(_nitroInfo.power.div(100));
                    }
                }
            }
        }
        return powerUp;
    }

    function unsafe_inc(uint256 x) private pure returns (uint256) {
        unchecked { return x + 1; }
    }

    function _getVaultAddress(uint256 vaultId) private view returns(address){
        return Vault[vaultId].nftAddress;
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