pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract SampleNFT is ERC721 {
    using Counters for Counters.Counter;

    Counters.Counter public _tokenIds;
    mapping(string => bool) public hashes;

    constructor() public ERC721("RANDOM NAME", "RND") {}

    /// wrapper on minting new 721
    function mint721(address _to, string memory _hash)
        public
        returns (uint256)
    {
        require(hashes[_hash] != true);
        hashes[_hash] = true;

        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();

        _safeMint(_to, newItemId);
        return newItemId;
    }
}
