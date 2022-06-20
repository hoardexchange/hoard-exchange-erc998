// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import "./ComposableTopDown.sol";
import "./ComposableTopDownERC1155.sol";
import "./ComposableTopDownERC20Enumerable.sol";


contract HoardBundles is ComposableTopDownERC1155, ComposableTopDownERC20Enumerable, Ownable, IERC721Metadata {

    /**
     * @dev Emitted when `owner` changes the base token uri.
     */
    event NewBaseURI(string baseURI);

    // Token name
    string public name;

    // Token symbol
    string public symbol;

    string public baseURI;

    uint256 public tokenCount = 0;

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) external view override returns (string memory) {
        require(tokenIdToTokenOwner[tokenId] != address(0), "CTD: URI does not exist");
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, toString(tokenId), ".json")) : "";
    }

    function setBaseURI(string calldata baseURI_) external onlyOwner {
        baseURI = baseURI_;
        emit NewBaseURI(baseURI_);
    }

    function safeMint(address to) external virtual {
        unchecked {
            tokenCount++;
        }
        _safeMint(to, tokenCount, "");
    }

    /**
     * @dev See {ComposableTopDown-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view override(ComposableTopDownERC1155, ComposableTopDownERC20Enumerable, IERC165) returns (bool) {
        return interfaceId == type(IERC721Metadata).interfaceId
            || ComposableTopDownERC20Enumerable.supportsInterface(interfaceId)
            || ComposableTopDownERC1155.supportsInterface(interfaceId);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     * Inspired by https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Strings.sol
     * The contract grew large and this is for size optimization purposes.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol
        unchecked {
            uint256 temp = value;
            uint256 digits;
            while (temp != 0) {
                digits++;
                temp /= 10;
            }
            bytes memory buffer = new bytes(digits);
            while (value != 0) {
                digits -= 1;
                buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
                value /= 10;
            }
            return string(buffer);
        }
    }
}
