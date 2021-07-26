// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


// Auditor b_s_u_v Thank you for looking at our contract ! 
//Let us know if our added notes are confusing at all.


contract Verify is Ownable {
    // NOTE FOR AUDIT//
    /*

    This entire Verify contract was taken from openzepplin, a more in depth explanation of what it does is at the link below.
    Since this code was copied from openzepplin it doesn't really need to be verified much
    Basically, all it does is ensure that the _verificationAddress signed the data. 
    The data is a _number and _word and sometimes also an _address. The signature is passed into the functions,
    and it then ensures that the signature is indeed from _verificationAddress
    https://blog.openzeppelin.com/signing-and-validating-ethereum-signatures/
    */


    address verificationAddress;
    constructor (address _verificationAddress) {
        verificationAddress = _verificationAddress;
    }

    function isValidData(uint256 _number, string memory _word, bytes memory sig) public view returns(bool){
        // Audit Note// 
        // This is the only important part of the function, it verifies that (_number, _word) was signed by _verificationaddress
        bytes32 message = keccak256(abi.encodePacked(_number, _word));
        return (recoverSigner(message, sig) == verificationAddress);
    }

    function isValidData(uint256 _number, string memory _word, address _address, bytes memory sig) public view returns(bool){
        // Audit Note// 
        // Verifies that (_number, _word, _address) was signed by _verificationAddress
        bytes32 message = keccak256(abi.encodePacked(_number, _word, _address));
        return (recoverSigner(message, sig) == verificationAddress);
    }

    function recoverSigner(bytes32 message, bytes memory sig) internal pure returns (address){
        uint8 v;
        bytes32 r;
        bytes32 s;
        (v, r, s) = splitSignature(sig);
        return ecrecover(message, v, r, s);
    }

    function splitSignature(bytes memory sig) internal pure returns (uint8, bytes32, bytes32) {
        require(sig.length == 65);
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
           // first 32 bytes, after the length prefix
           r := mload(add(sig, 32))
           // second 32 bytes
           s := mload(add(sig, 64))
           // final byte (first byte of the next 32 bytes)
           v := byte(0, mload(add(sig, 96)))
        }
        return (v, r, s);
   }

   // Owner Functions
   function setVerificationAddress(address _verificationAddress) public onlyOwner {
        verificationAddress = _verificationAddress;
    }
}

interface Cryptopunks {
    // NOTE FOR AUDIT//
    // We just need the owner of the famous punk nfts at index so we use this small interface.
    function punkIndexToAddress(uint index) external view returns(address);
}

contract Cybernetics is ERC721, ERC721Enumerable, Verify, ReentrancyGuard{
    constructor(address _verificationAddress, string memory _base) ERC721("Puppy3", "PUP2") Verify(_verificationAddress){
        baseURI = _base; // for metadata standard points to our website to see token data
    }

    string private baseURI = ""; // Audit Note: Base URI for metadata is passed in during the constructor
    uint256 public constant MAX_SUPPLY = 10000; // Audit Note: No more than 10,000 should ever be minted

    uint256 public mintPrice = 100000000000000000; // 0.1 ETH
    bool public communityGrant = false; // Audit Note: this will be turned on when the punks can mint for free
    bool public publicSale = false; // Audit Note: Will be turned on when people can pay for mints
    
    mapping(uint256 => address) public originalMinters; // Audit Note, we want to keep a list of original minters for special rewards. Should never change after mint

    mapping (uint256 => uint256) internal punksUsedBlock; // Audit: special hashing of punks used in the last 10 blocks for winning the game explained in mintWithPunk function
    mapping (uint256 => uint256) public giveawaysUsed; // Audit: simple dictionary of giveaway numbers used to the number 1 if used 0 if not
    //address internal punksAddress = 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB; //mainnet punk address
    address internal punksAddress = 0x424f62Dd208074FbD4BfBE4B99844638F306bEA1; // rinkeby punk address (can claim punks here for testing purposes)
    uint256 public punkMintsRemaining = 250; // Audit: only 250 free mints for punks
    uint256 public giveawaysRemaining = 200; // Audit: only 200 free 
    uint256 randomMintMod = 3; // Audit: 1/3 chance of winning random game explained in getTokenBlockHash (Start in mintWithPunk function)
    uint256 blockRoundMod = 10; //Audit: Round every 10 blocks, used in the random Game for punks explained in getTokenBlockHash (Start in mintWithPunk function)

    // Audit: Optional contract-accessible base64 image encoding, explained more in saveTokenImage
    mapping (uint256 => string) public tokenToImage;


    function _mintCybernetic(address _to) internal {
        // NOTE FOR AUDIT//
        // We simply mint one cybernetic nft making sure we stay under max supply
        require(totalSupply() < MAX_SUPPLY, 'Reached max supply');
        _safeMint(_to, totalSupply()); // totalSupply is new ID
        originalMinters[totalSupply()] = _to;
    }   

    /*
     * Image and Contract Data is already accessible through the blockchain for every token via uploadData(),
     * but it's accessible via outside calls only. For individual images to be accessible to /contracts/, 
     * users can optionally save the base64 encoding of their tokens here.
     */
    function saveTokenImage(uint256 _tokenId, string memory imageData, bytes memory sig) public {
        // NOTE FOR AUDIT//
        // Here we use the verify contract to let the user upload a string of "imageData". 
        // The devs could do this but it would cost a lot of gas, so the user has the option to upload the data themselves
        // Here we just ensure the signature matches the signed image data. We must the user can only upload valid data for that token
        // It's okay for anyone to call this method as long as the iamgeData is valid and signed by the verificationaddress
        require(isValidData(_tokenId, imageData, sig), "Invalid Sig");
        require(bytes(tokenToImage[_tokenId]).length == 0, "Cannot change imageData");
        tokenToImage[_tokenId] = imageData;
    }

    function mintPublic(uint256 mintAmt) external payable nonReentrant{
        // NOTE FOR AUDIT//
        // This is our public sale function. The devs must turn on the publicSale bool. They can't mint more than 20 at a time
        // We must make sure they pay the mintPrice (which devs can set in anotehr function) multiplied by the number of nfts they want
        // making sure it doesn't go over the max supply is checked in _mintCybernetic function
        require(publicSale);
        require(mintAmt > 0 && mintAmt <= 20, "Must mint between 1 and 20");
        require(msg.value >= mintPrice*mintAmt, 'Eth value below price');
        for (uint256 i = 0; i < mintAmt; i++) {
            _mintCybernetic(msg.sender);
        }
    }

    function giveawayMint(uint256 number, bytes memory sig) external nonReentrant {
        // NOTE FOR AUDIT//
        // This is our free giveaway function. Anyone who has the secret signature that we send them
        // Can then use it to mint one free nft. The signed message by the verificationaddress
        // will be the number of the free giveway and then the string "giveaway". 
        // We have to make sure that each number/signature is only used once and that the sig is valid
        // also we have to make sure that there are giveawaysRemaining (which can be changed by devs if need be), decreases every call
        require(isValidData(number, "giveaway", sig) || isValidData(number, "giveaway", msg.sender, sig), "Invalid Sig");
        require(giveawaysUsed[number] == 0, "Already minted with this giveaway");
        require(giveawaysRemaining > 0, "No giveaway mints remaining");
        giveawaysUsed[number]++;
        giveawaysRemaining--;
        _mintCybernetic(msg.sender);
    }

    /**
     * Community grant minting.
     */
    function mintWithPunk(uint256 _punkId) external nonReentrant {
        // NOTE FOR AUDIT //
        /// This is a more complex function for a random game!! 
        // Punks are a famous nft that started everything.
        // We want to allow people who own punks to be able to claim some free nfts in a fun game explained in steps below
        
        // First we make sure communityGrant bool is on (devs can set this), so we know game has started) set by devs)
        // Then we ensure the caller of this function owns the punk
        // We also make sure the punkMintsRemaining is still above 0 (devs can change this.) 
        // This number Decreases every call
        // then we call our special lottery function in "checkAndMarkBlock" to see if they won the lottery
        // Only people who won this lottery get to mint one. 
        //You can win one lottery every 10 blocks, even with only one punk

        // We explain the random number generator lottery more in below functions!

        // For auditor, If you need to claim a rinkeby punk or look at punk contract, the rinkeby address and mainnet address is up top
        // We can also explain anything confusing too.

        require(communityGrant, "Community Grant is off");
        require(Cryptopunks(punksAddress).punkIndexToAddress(_punkId) == msg.sender, "Not the punk owner.");
        require(punkMintsRemaining > 0, "No punk mints remaining");
        
        /* Hash Check */
        checkAndMarkBlock(_punkId);

        punkMintsRemaining--;
        _mintCybernetic(msg.sender);
    }

    function checkAndMarkBlock(uint256 _punkId) internal {
        // NOTE FOR AUDIT //
        // First we hash the punk with the block number (we round the block number down to nearest 10)
        // This is done and described in getTokenBlockHash
        // Each hash should be the same across 10 blocks (assuming same punkId). 
        // So 0-9 blocks will have same hash
        
        // We must check that this hash hasn't been used before by checking punksUsedBlock dictionary
        // Make sure it's 0, so it's never been used
        // This is so if they win once they cannot just get all the punk mints right away 
        // that would be bad and ruin the game.
        // But also, after the 10 blocks is up they can continue the game again with the same punk
        
        // We take the unused hash from getTokenBlockHash and put it into internalWinningHash function 
        // This checks to see if that hash is a winning one. The process is described there
        
        uint256 tokenBlockHash = getTokenBlockHash(_punkId, block.number);
        require(punksUsedBlock[tokenBlockHash] == 0, "Punk already used this block");
        require(internalWinningHash(tokenBlockHash), "Try again, bad timing");
        punksUsedBlock[tokenBlockHash]++;
    }

    function checkWinningHash(uint _punkId, uint blockNumber) public view returns (bool){
        // Audit Note // 
        // This is a public function so that people can check it before trying to win (so they don't waste gas)
        
        // The reason we pass in blockNumber instead of doing block.number directly in the function,
        // is because we want external users to be able to check if their punk id and block will work
        // before they call the function. 

        // In ethereum if you call the function externally it would be one number off 
        // As the external read functions use block.number of the last mined block not the next potential block
        
        // So with the blockNumber parameter, they can pass in the next blockNumber that will be mined.
        // We can talk more about the checking logic on the website if you don't understand this part 
        // Or if we explained badly the off-by one view part, just ask us
        
        uint256 tokenBlockHash = getTokenBlockHash(_punkId, blockNumber);
        return internalWinningHash(tokenBlockHash);
    }

    function internalWinningHash(uint256 tokenBlockHash) internal view returns (bool){
        // Audit Note // 
        // This is the part where we mod the random hash of the punk and block with randomMintMod 
        // This is to determine if it's a winning hash or not
        // You pass in the hash you got from getTokenBlockHash, and you mod it by randomMintMod
        
        // Right now randomMintMod = 3 (can be changed by devs) 
        // This  means that the index can be 0, 1, or 2
        
        // Thus any hash has a 1/3 chance of being equal to 0, which makes it a winner

        uint256 index = tokenBlockHash % randomMintMod;
        return (index == 0);
    }

    function checkPunkUnusedThisBlock(uint _punkId, uint blockNumber) public view returns (bool){
        // Audit Note // 
        // This is an outside function that can be used to make sure the punk hasn't been used to win already
        // It checks to see if it's been used in the past 10 blocks
        
        // This is for calling outside the contract
        // So that our website can check beforehand and make sure the user isn't wasting gas.
        // They can use the punk again in 10 blocks

        uint256 tokenBlockHash = getTokenBlockHash(_punkId, blockNumber);
        return (punksUsedBlock[tokenBlockHash] == 0);
    }

    function getTokenBlockHash(uint _tokenId, uint blockNumber) internal view returns (uint){
        // Audit Note // 

        // Here is how to get the tokenBlockHash that is used for the random game!
        // First we round down the blockNumber with blockRoundMod. Right now blockRoundMod is 10, so
        // So Block 28 and Block 22 both round down to 20 and should producue the same hash every time
        // Block 30 would be the start of a new randomHash and new "try" for the punk owner to mint

        // Then we simply hash the block rounded down with the tokenId so every punk has a different hash
        
        // The reason for passing in the blockNumber is explained in checkWinningHash function 
        // (It's so it can be used externally too)
        
        uint256 blockRounded = blockNumber - (blockNumber % blockRoundMod);
        uint256 tokenBlockHash = uint(keccak256(abi.encodePacked(_tokenId, blockRounded)));
        return tokenBlockHash;
    }


    // Function exists solely for ease of metadata standards
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }



    // Owner Functions
    // Audit Note //
    // All owner functions should only be able to be called by the owner of the contract
    // This is whoever deploys it, unless the devs set it to someone else in the ownable openzepplin contract

    function setMintPrice(uint256 _mintPrice) public onlyOwner {
        mintPrice = _mintPrice;
    }

    function setCommunityGrant(bool _communityGrant) public onlyOwner {
        communityGrant = _communityGrant;
    }

    function setPublicSale(bool _publicSale) public onlyOwner {
        publicSale = _publicSale;
    }

    function setPunkMints(uint256 _punkMints) public onlyOwner {
        punkMintsRemaining = _punkMints;
    }

    function setGiveaways(uint256 _giveawayMints) public onlyOwner {
        giveawaysRemaining = _giveawayMints;
    }

    function setRandomMintMod(uint256 _mod) public onlyOwner {
        randomMintMod = _mod;
    }

    function setBlockRoundMod(uint256 _mod) public onlyOwner {
        blockRoundMod = _mod;
    }

    function setBaseURI(string memory _base) public onlyOwner {
        baseURI = _base;
    }

    function withdraw(uint256 _amount) public onlyOwner {
        // Audit Note //
        // Should be simple and explanatory, we just need to be able to withdraw the money //
        require(payable(msg.sender).send(_amount));
    }

    function withdrawAll() public onlyOwner {
        require(payable(msg.sender).send(address(this).balance));
    }

    function devMint(uint mintAmt) public onlyOwner {
        // Audit Note // 
        // Devs and only devs should be able to mint as many as they want for free.//
        for (uint256 i = 0; i < mintAmt; i++) {
            _mintCybernetic(msg.sender);
        }
    }

    function devAirdrop(address[] memory dropAddresses) public onlyOwner {
        // Audit Note// 
        // Here we provide a list of addresses if we want to give them free tokens. 
        // We do this so they're the original owners documented in the originalMinters dictionary
        // This is better than minting first and then sending after

        for (uint256 i = 0; i < dropAddresses.length; i++) {
            _mintCybernetic(dropAddresses[i]);
        }
    }

    function uploadData(bytes[] memory _data) public onlyOwner {
        // Audit Note// 
        // This is for devs only to upload all the images hashed together to the blockchain. 
        // It is too expensive to save this on storage which is why individual owners can do so themselves 
        // if they wish with our saveTokenImage function above 
        // Even though it's not saved on storage, it can be accessed in logs by etherscan so that is always with the blockchain
        // We know it is not accessible on-chain by contracts however but 10,000 images is too many
        emit UploadData();
    }

    event UploadData();

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        // Audit Note// 
        // These two functions were copied from openzepplin. We are not really sure if they are necessary,
        // But we wanted to make sure that ERC721Enumerable was properly implemented so we included them.
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
