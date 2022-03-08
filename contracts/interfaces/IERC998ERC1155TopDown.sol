// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IERC998ERC1155TopDown {
//    event ReceivedERC20(address indexed _from, uint256 indexed _tokenId, address indexed _erc20Contract, uint256 _value);
    event TransferERC1155(uint256 _fromTokenId, address _to, address _erc1155Contract, uint256 _childTokenId, uint256 _amount);
    event BatchTransferERC1155(uint256 _fromTokenId, address _to, address _erc1155Contract, uint256[] _childTokenIds, uint256[] _amounts);
    event ReceivedErc1155(
        address indexed _from,
        uint256 indexed _tokenId,
        address indexed _childContract,
        uint256 _childTokenId,
        uint256 _amount
    );
    event ReceivedBatchErc1155(
        address indexed _from,
        uint256 indexed _tokenId,
        address indexed _childContract,
        uint256[] _childTokenIds,
        uint256[] _amounts
    );

    /**
     * @dev See {IERC1155-safeTransferFrom}.
     */
    function safeTransferFromERC1155(
        uint256 _fromTokenId,
        address _to,
        address _erc1155Contract,
        uint256 _childTokenId,
        uint256 _amount,
        bytes memory _data
    ) external;

    /**
     * @dev See {IERC1155-safeBatchTransferFrom}.
     */
    function safeBatchTransferFromERC1155(
        uint256 _fromTokenId,
        address _to,
        address _erc1155Contract,
        uint256[] memory _childTokenIds,
        uint256[] memory _amounts,
        bytes memory _data
    ) external;

    /**
     * @dev See {IERC1155-balanceOf}.
     */
    function balanceOfERC1155(uint256 _tokenId, address _erc1155Contract, uint256 childTokenId)
        external
        view
        returns (uint256);

    /**
     * @dev See {IERC1155-balanceOfBatch}.
     */
    function balanceOfBatchERC1155(uint256[] memory _tokenIds, address _erc1155Contract, uint256[] memory childTokenIds)
        external
        view
        returns (uint256[] memory);

}