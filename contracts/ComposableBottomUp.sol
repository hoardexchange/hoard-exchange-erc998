// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import "@openzeppelin/contracts/introspection/ERC165.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "./interfaces/IERC998ERC721BottomUp.sol";
import "./interfaces/IERC998ERC721BottomUpEnumerable.sol";

contract ComposableBottomUp is
    ERC165,
    IERC721,
    IERC998ERC721BottomUp,
    IERC998ERC721BottomUpEnumerable
{
    using SafeMath for uint256;
    struct TokenOwner {
        address tokenOwner;
        uint256 parentTokenId;
    }

    // return this.rootOwnerOf.selector ^ this.rootOwnerOfChild.selector ^
    //   this.tokenOwnerOf.selector ^ this.ownerOfChild.selector;
    bytes4 constant ERC998_MAGIC_VALUE = 0xcd740db5;

    // tokenId => token owner
    mapping(uint256 => TokenOwner) internal tokenIdToTokenOwner;

    // root token owner address => (tokenId => approved address)
    mapping(address => mapping(uint256 => address))
        internal rootOwnerAndTokenIdToApprovedAddress;

    // token owner address => token count
    mapping(address => uint256) internal tokenOwnerToTokenCount;

    // token owner => (operator address => bool)
    mapping(address => mapping(address => bool)) internal tokenOwnerToOperators;

    // parent address => (parent tokenId => array of child tokenIds)
    mapping(address => mapping(uint256 => uint256[]))
        private parentToChildTokenIds;

    // tokenId => position in childTokens array
    mapping(uint256 => uint256) private tokenIdToChildTokenIdsIndex;

    // wrapper on minting new 721
    /*
    function mint721(address _to) public returns(uint256) {
      _mint(_to, allTokens.length + 1);
      return allTokens.length;
    }
    */
    //from zepellin ERC721Receiver.sol
    //old version
    bytes4 constant ERC721_RECEIVED = 0x150b7a02;

    function isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }

    function _tokenOwnerOf(uint256 _tokenId)
        internal
        view
        returns (
            address tokenOwner,
            uint256 parentTokenId,
            bool isParent
        )
    {
        tokenOwner = tokenIdToTokenOwner[_tokenId].tokenOwner;
        require(
            tokenOwner != address(0),
            "ComposableBottomUp: _tokenOwnerOf tokenOwner zero address"
        );
        parentTokenId = tokenIdToTokenOwner[_tokenId].parentTokenId;
        if (parentTokenId > 0) {
            isParent = true;
            parentTokenId--;
        } else {
            isParent = false;
        }
        return (tokenOwner, parentTokenId, isParent);
    }

    function tokenOwnerOf(uint256 _tokenId)
        external
        view
        override
        returns (
            bytes32 tokenOwner,
            uint256 parentTokenId,
            bool isParent
        )
    {
        address tokenOwnerAddress = tokenIdToTokenOwner[_tokenId].tokenOwner;
        require(tokenOwnerAddress != address(0), "ComposableBottomUp: tokenOwnerOf tokenOwnerAddress zero address");
        parentTokenId = tokenIdToTokenOwner[_tokenId].parentTokenId;
        if (parentTokenId > 0) {
            isParent = true;
            parentTokenId--;
        } else {
            isParent = false;
        }
        return (
            (ERC998_MAGIC_VALUE << 224) |
                bytes32(uint256(uint160(tokenOwnerAddress))),
            parentTokenId,
            isParent
        );
    }

    // Use Cases handled:
    // Case 1: Token owner is this contract and no parent tokenId.
    // Case 2: Token owner is this contract and token
    // Case 3: Token owner is top-down composable
    // Case 4: Token owner is an unknown contract
    // Case 5: Token owner is a user
    // Case 6: Token owner is a bottom-up composable
    // Case 7: Token owner is ERC721 token owned by top-down token
    // Case 8: Token owner is ERC721 token owned by unknown contract
    // Case 9: Token owner is ERC721 token owned by user
    function rootOwnerOf(uint256 _tokenId)
        public
        view
        override
        returns (bytes32 rootOwner)
    {
        address rootOwnerAddress = tokenIdToTokenOwner[_tokenId].tokenOwner;
        require(
            rootOwnerAddress != address(0),
            "ComposableBottomUp: rootOwnerOf rootOwnerAddress zero address"
        );
        uint256 parentTokenId = tokenIdToTokenOwner[_tokenId].parentTokenId;
        bool isParent = parentTokenId > 0;
        parentTokenId--;
        bytes memory callData;
        bytes memory data;
        bool callSuccess;

        if ((rootOwnerAddress == address(this))) {
            do {
                if (isParent == false) {
                    // Case 1: Token owner is this contract and no token.
                    // This case should not happen.
                    return
                        (ERC998_MAGIC_VALUE << 224) |
                        bytes32(uint256(uint160(rootOwnerAddress)));
                } else {
                    // Case 2: Token owner is this contract and token
                    (rootOwnerAddress, parentTokenId, isParent) = _tokenOwnerOf(
                        parentTokenId
                    );
                }
            } while (rootOwnerAddress == address(this));
            _tokenId = parentTokenId;
        }

        if (isParent == false) {
            // success if this token is owned by a top-down token
            // 0xed81cdda == rootOwnerOfChild(address, uint256)
            callData = abi.encodeWithSelector(
                0xed81cdda,
                address(this),
                _tokenId
            );
            (callSuccess, data) = rootOwnerAddress.staticcall(callData);
            if (callSuccess) {
                assembly {
                    rootOwner := mload(add(data, 0x20))
                }
            }
            if (callSuccess == true && rootOwner >> 224 == ERC998_MAGIC_VALUE) {
                // Case 3: Token owner is top-down composable
                return rootOwner;
            } else {
                // Case 4: Token owner is an unknown contract
                // Or
                // Case 5: Token owner is a user
                return
                    (ERC998_MAGIC_VALUE << 224) |
                    bytes32(uint256(uint160(rootOwnerAddress)));
            }
        } else {
            // 0x43a61a8e == rootOwnerOf(uint256)
            callData = abi.encodeWithSelector(0x43a61a8e, parentTokenId);
            (callSuccess, data) = rootOwnerAddress.staticcall(callData);
            if (callSuccess) {
                assembly {
                    rootOwner := mload(add(data, 0x20))
                }
            }
            if (callSuccess == true && rootOwner >> 224 == ERC998_MAGIC_VALUE) {
                // Case 6: Token owner is a bottom-up composable
                // Or
                // Case 2: Token owner is top-down composable
                return rootOwner;
            } else {
                // token owner is ERC721
                address childContract = rootOwnerAddress;
                //0x6352211e == "ownerOf(uint256)"
                callData = abi.encodeWithSelector(0x6352211e, parentTokenId);
                (callSuccess, data) = rootOwnerAddress.staticcall(callData);
                if (callSuccess) {
                    assembly {
                        rootOwnerAddress := mload(add(data, 0x20))
                    }
                }
                require(callSuccess, "Call to ownerOf failed");

                // 0xed81cdda == rootOwnerOfChild(address,uint256)
                callData = abi.encodeWithSelector(
                    0xed81cdda,
                    childContract,
                    parentTokenId
                );

                (callSuccess, data) = rootOwnerAddress.staticcall(callData);
                if (callSuccess) {
                    assembly {
                        rootOwner := mload(add(data, 0x20))
                    }
                }
                if (
                    callSuccess == true &&
                    rootOwner >> 224 == ERC998_MAGIC_VALUE
                ) {
                    // Case 7: Token owner is ERC721 token owned by top-down token
                    return rootOwner;
                } else {
                    // Case 8: Token owner is ERC721 token owned by unknown contract
                    // Or
                    // Case 9: Token owner is ERC721 token owned by user
                    return
                        (ERC998_MAGIC_VALUE << 224) |
                        bytes32(uint256(uint160(rootOwnerAddress)));
                }
            }
        }
    }

    /**
     * In a bottom-up composable authentication to transfer etc. is done by getting the rootOwner by finding the parent token
     * and then the parent token of that one until a final owner address is found.  If the msg.sender is the rootOwner or is
     * approved by the rootOwner then msg.sender is authenticated and the action can occur.
     * This enables the owner of the top-most parent of a tree of composables to call any method on child composables.
     */
    // returns the root owner at the top of the tree of composables
    function ownerOf(uint256 _tokenId) public view override returns (address) {
        address tokenOwner = tokenIdToTokenOwner[_tokenId].tokenOwner;
        require(
            tokenOwner != address(0),
            "ComposableBottomUp: ownerOf tokenOwner zero address"
        );
        return tokenOwner;
    }

    function balanceOf(address _tokenOwner)
        external
        view
        override
        returns (uint256)
    {
        require(
            _tokenOwner != address(0),
            "ComposableBottomUp: balanceOf _tokenOwner zero address"
        );
        return tokenOwnerToTokenCount[_tokenOwner];
    }

    function approve(address _approved, uint256 _tokenId) external override {
        address tokenOwner = tokenIdToTokenOwner[_tokenId].tokenOwner;
        require(tokenOwner != address(0), "ComposableBottomUp: approve tokenOwner zero address");
        address rootOwner = address(uint160(uint256(rootOwnerOf(_tokenId))));
        require(
            rootOwner == msg.sender ||
                tokenOwnerToOperators[rootOwner][msg.sender],
            "ComposableBottomUp: approve msg.sender not eligible"
        );

        rootOwnerAndTokenIdToApprovedAddress[rootOwner][_tokenId] = _approved;
        emit Approval(rootOwner, _approved, _tokenId);
    }

    function getApproved(uint256 _tokenId)
        public
        view
        override
        returns (address)
    {
        address rootOwner = address(uint160(uint256(rootOwnerOf(_tokenId))));
        return rootOwnerAndTokenIdToApprovedAddress[rootOwner][_tokenId];
    }

    function setApprovalForAll(address _operator, bool _approved)
        external
        override
    {
        require(_operator != address(0), "ComposableBottomUp: setApprovalForAll _operator zero address");
        tokenOwnerToOperators[msg.sender][_operator] = _approved;
        emit ApprovalForAll(msg.sender, _operator, _approved);
    }

    function isApprovedForAll(address _owner, address _operator)
        external
        view
        override
        returns (bool)
    {
        require(_owner != address(0), "ComposableBottomUp: isApprovedForAll _owner zero address");
        require(_operator != address(0), "ComposableBottomUp: isApprovedForAll _operator zero address");
        return tokenOwnerToOperators[_owner][_operator];
    }

    function removeChild(
        address _fromContract,
        uint256 _fromTokenId,
        uint256 _tokenId
    ) internal {
        uint256 childTokenIndex = tokenIdToChildTokenIdsIndex[_tokenId];
        uint256 lastChildTokenIndex =
            parentToChildTokenIds[_fromContract][_fromTokenId].length - 1;
        uint256 lastChildTokenId =
            parentToChildTokenIds[_fromContract][_fromTokenId][
                lastChildTokenIndex
            ];

        if (_tokenId != lastChildTokenId) {
            parentToChildTokenIds[_fromContract][_fromTokenId][
                childTokenIndex
            ] = lastChildTokenId;
            tokenIdToChildTokenIdsIndex[lastChildTokenId] = childTokenIndex;
        }
        // parentToChildTokenIds[_fromContract][_fromTokenId].length--;
        // added:
        parentToChildTokenIds[_fromContract][_fromTokenId].pop();
    }

    function authenticateAndClearApproval(uint256 _tokenId) private {
        address rootOwner = address(uint160(uint256(rootOwnerOf(_tokenId))));
        address approvedAddress =
            rootOwnerAndTokenIdToApprovedAddress[rootOwner][_tokenId];
        require(
            rootOwner == msg.sender ||
                tokenOwnerToOperators[rootOwner][msg.sender] ||
                approvedAddress == msg.sender,
            "ComposableBottomUp: authenticateAndClearApproval msg.sender not eligible"
        );

        // clear approval
        if (approvedAddress != address(0)) {
            delete rootOwnerAndTokenIdToApprovedAddress[rootOwner][_tokenId];
            emit Approval(rootOwner, address(0), _tokenId);
        }
    }

    function transferFromParent(
        address _fromContract,
        uint256 _fromTokenId,
        address _to,
        uint256 _tokenId,
        bytes memory _data
    ) external override {
        require(tokenIdToTokenOwner[_tokenId].tokenOwner == _fromContract, "ComposableBottomUp: transferFromParent tokenOwner != _fromContract");
        require(_to != address(0), "ComposableBottomUp: transferFromParent _to zero address");
        uint256 parentTokenId = tokenIdToTokenOwner[_tokenId].parentTokenId;
        require(parentTokenId != 0, "ComposableBottomUp: transferFromParent token does not have a parent token.");
        require(parentTokenId - 1 == _fromTokenId, "ComposableBottomUp: transferFromParent _fromTokenId not matching parentTokenId");
        authenticateAndClearApproval(_tokenId);

        // remove and transfer token
        if (_fromContract != _to) {
            assert(tokenOwnerToTokenCount[_fromContract] > 0);
            tokenOwnerToTokenCount[_fromContract]--;
            tokenOwnerToTokenCount[_to]++;
        }

        tokenIdToTokenOwner[_tokenId].tokenOwner = _to;
        tokenIdToTokenOwner[_tokenId].parentTokenId = 0;

        removeChild(_fromContract, _fromTokenId, _tokenId);
        delete tokenIdToChildTokenIdsIndex[_tokenId];

        if (isContract(_to)) {
            bytes4 retval =
                IERC721Receiver(_to).onERC721Received(
                    msg.sender,
                    _fromContract,
                    _tokenId,
                    _data
                );
            require(retval == ERC721_RECEIVED, "ComposableBottomUp: transferFromParent onERC721Received invalid value");
        }

        emit Transfer(_fromContract, _to, _tokenId);
        emit TransferFromParent(_fromContract, _fromTokenId, _tokenId);
    }

    function transferToParent(
        address _from,
        address _toContract,
        uint256 _toTokenId,
        uint256 _tokenId,
        bytes memory _data
    ) external override {
        require(_from != address(0), "ComposableBottomUp: transferToParent _from zero address");
        require(tokenIdToTokenOwner[_tokenId].tokenOwner == _from, "ComposableBottomUp: transferToParent tokenOwner != _from");
        require(_toContract != address(0), "ComposableBottomUp: transferToParent _toContract zero address");
        require(
            tokenIdToTokenOwner[_tokenId].parentTokenId == 0,
            "ComposableBottomUp: transferToParent Cannot transfer from address when owned by a token."
        );
        address approvedAddress =
            rootOwnerAndTokenIdToApprovedAddress[_from][_tokenId];
        if (msg.sender != _from) {
            // 0xed81cdda == rootOwnerOfChild(address,uint256)
            bytes memory callData =
                abi.encodeWithSelector(0xed81cdda, address(this), _tokenId);
            (bool callSuccess, bytes memory data) = _from.staticcall(callData);
            if (callSuccess == true) {
                bytes32 rootOwner;
                assembly {
                    rootOwner := mload(add(data, 0x20))
                }
                require(
                    rootOwner >> 224 != ERC998_MAGIC_VALUE,
                    "ComposableBottomUp: transferToParent Token is child of other top down composable"
                );
            }
            require(
                tokenOwnerToOperators[_from][msg.sender] ||
                    approvedAddress == msg.sender,
                    "ComposableBottomUp: transferToParent msg.sender is not eligible"
            );
        }

        // clear approval
        if (approvedAddress != address(0)) {
            delete rootOwnerAndTokenIdToApprovedAddress[_from][_tokenId];
            emit Approval(_from, address(0), _tokenId);
        }

        // remove and transfer token
        if (_from != _toContract) {
            assert(tokenOwnerToTokenCount[_from] > 0);
            tokenOwnerToTokenCount[_from]--;
            tokenOwnerToTokenCount[_toContract]++;
        }
        TokenOwner memory parentToken =
            TokenOwner(_toContract, _toTokenId.add(1));
        tokenIdToTokenOwner[_tokenId] = parentToken;
        uint256 index = parentToChildTokenIds[_toContract][_toTokenId].length;
        parentToChildTokenIds[_toContract][_toTokenId].push(_tokenId);
        tokenIdToChildTokenIdsIndex[_tokenId] = index;

        require(
            IERC721(_toContract).ownerOf(_toTokenId) != address(0),
            "ComposableBottomUp: transferToParent _toTokenId does not exist"
        );

        emit Transfer(_from, _toContract, _tokenId);
        emit TransferToParent(_toContract, _toTokenId, _tokenId);
    }

    function transferAsChild(
        address _fromContract,
        uint256 _fromTokenId,
        address _toContract,
        uint256 _toTokenId,
        uint256 _tokenId,
        bytes memory _data
    ) external override {
        require(tokenIdToTokenOwner[_tokenId].tokenOwner == _fromContract, "ComposableBottomUp: transferAsChild tokenOwner != _fromContract");
        require(_toContract != address(0), "ComposableBottomUp: transferAsChild _toContract zero address");
        uint256 parentTokenId = tokenIdToTokenOwner[_tokenId].parentTokenId;
        require(parentTokenId > 0, "ComposableBottomUp: transferAsChild No parent token to transfer from.");
        require(parentTokenId - 1 == _fromTokenId, "ComposableBottomUp: transferAsChild parentTokenId != _fromTokenId");
        address rootOwner = address(uint160(uint256(rootOwnerOf(_tokenId))));
        address approvedAddress =
            rootOwnerAndTokenIdToApprovedAddress[rootOwner][_tokenId];
        require(
            rootOwner == msg.sender ||
                tokenOwnerToOperators[rootOwner][msg.sender] ||
                approvedAddress == msg.sender,
                "ComposableBottomUp: transferAsChild msg.sender not eligible"
        );
        // clear approval
        if (approvedAddress != address(0)) {
            delete rootOwnerAndTokenIdToApprovedAddress[rootOwner][_tokenId];
            emit Approval(rootOwner, address(0), _tokenId);
        }

        // remove and transfer token
        if (_fromContract != _toContract) {
            assert(tokenOwnerToTokenCount[_fromContract] > 0);
            tokenOwnerToTokenCount[_fromContract]--;
            tokenOwnerToTokenCount[_toContract]++;
        }

        TokenOwner memory parentToken = TokenOwner(_toContract, _toTokenId);
        tokenIdToTokenOwner[_tokenId] = parentToken;

        removeChild(_fromContract, _fromTokenId, _tokenId);

        //add to parentToChildTokenIds
        uint256 index = parentToChildTokenIds[_toContract][_toTokenId].length;
        parentToChildTokenIds[_toContract][_toTokenId].push(_tokenId);
        tokenIdToChildTokenIdsIndex[_tokenId] = index;

        require(
            IERC721(_toContract).ownerOf(_toTokenId) != address(0),
            "ComposableBottomUp: transferAsChild _toTokenId does not exist"
        );

        emit Transfer(_fromContract, _toContract, _tokenId);
        emit TransferFromParent(_fromContract, _fromTokenId, _tokenId);
        emit TransferToParent(_toContract, _toTokenId, _tokenId);
    }

    function _transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) private {
        require(_from != address(0), "ComposableBottomUp: _transferFrom _from zero address");
        require(tokenIdToTokenOwner[_tokenId].tokenOwner == _from, "ComposableBottomUp: _transferFrom tokenOwner != _from");
        require(
            tokenIdToTokenOwner[_tokenId].parentTokenId == 0,
            "ComposableBottomUp: _transferFrom Cannot transfer from address when owned by a token."
        );
        require(_to != address(0), "ComposableBottomUp: _transferFrom _to zero address");
        address approvedAddress =
            rootOwnerAndTokenIdToApprovedAddress[_from][_tokenId];
        if (msg.sender != _from) {
            // 0xed81cdda == rootOwnerOfChild(address,uint256)
            bytes memory callData =
                abi.encodeWithSelector(0xed81cdda, address(this), _tokenId);
            (bool callSuccess, bytes memory data) = _from.staticcall(callData);
            if (callSuccess == true) {
                bytes32 rootOwner;
                if (callSuccess) {
                    assembly {
                        rootOwner := mload(add(data, 0x20))
                    }
                }
                require(
                    rootOwner >> 224 != ERC998_MAGIC_VALUE,
                    "ComposableBottomUp: _transferFrom Token is child of other top down composable"
                );
            }
            require(
                tokenOwnerToOperators[_from][msg.sender] ||
                    approvedAddress == msg.sender,
                    "ComposableBottomUp: _transferFrom msg.sender not eligible"
            );
        }

        // clear approval
        if (approvedAddress != address(0)) {
            delete rootOwnerAndTokenIdToApprovedAddress[_from][_tokenId];
            emit Approval(_from, address(0), _tokenId);
        }

        // remove and transfer token
        if (_from != _to) {
            assert(tokenOwnerToTokenCount[_from] > 0);
            tokenOwnerToTokenCount[_from]--;
            tokenIdToTokenOwner[_tokenId].tokenOwner = _to;
            tokenOwnerToTokenCount[_to]++;
        }
        emit Transfer(_from, _to, _tokenId);
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) external override {
        _transferFrom(_from, _to, _tokenId);
    }

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) external override {
        _transferFrom(_from, _to, _tokenId);
        if (isContract(_to)) {
            bytes4 retval =
                IERC721Receiver(_to).onERC721Received(
                    msg.sender,
                    _from,
                    _tokenId,
                    ""
                );
            require(retval == ERC721_RECEIVED, "ComposableBottomUp: safeTransferFrom(3) onERC721Received invalid value");
        }
    }

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        bytes memory _data
    ) external override {
        _transferFrom(_from, _to, _tokenId);
        if (isContract(_to)) {
            bytes4 retval =
                IERC721Receiver(_to).onERC721Received(
                    msg.sender,
                    _from,
                    _tokenId,
                    _data
                );
            require(retval == ERC721_RECEIVED, "ComposableBottomUp: safeTransferFrom(4) onERC721Received invalid value");
        }
    }

    function totalChildTokens(address _parentContract, uint256 _parentTokenId)
        public
        view
        override
        returns (uint256)
    {
        return parentToChildTokenIds[_parentContract][_parentTokenId].length;
    }

    function childTokenByIndex(
        address _parentContract,
        uint256 _parentTokenId,
        uint256 _index
    ) public view override returns (uint256) {
        require(
            parentToChildTokenIds[_parentContract][_parentTokenId].length >
                _index,
                "ComposableBottomUp: childTokenByIndex invalid _index"
        );
        return parentToChildTokenIds[_parentContract][_parentTokenId][_index];
    }
}
