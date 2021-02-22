pragma solidity ^0.7.0;

interface IERC998ERC721BottomUpEnumerable {
    function totalChildTokens(address _parentContract, uint256 _parentTokenId)
        external
        view
        returns (uint256);

    function childTokenByIndex(
        address _parentContract,
        uint256 _parentTokenId,
        uint256 _index
    ) external view returns (uint256);
}
