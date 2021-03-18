// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import "@openzeppelin/contracts/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";

import "./interfaces/IERC20AndERC223.sol";
import "./interfaces/IERC998ERC20TopDown.sol";
import "./interfaces/IERC998ERC20TopDownEnumerable.sol";
import "./interfaces/IERC998ERC721BottomUp.sol";
import "./interfaces/IERC998ERC721TopDown.sol";
import "./interfaces/IERC998ERC721TopDownEnumerable.sol";

contract ComposableTopDown is
    ERC165,
    IERC721,
    IERC998ERC721TopDown,
    IERC998ERC721TopDownEnumerable,
    IERC998ERC20TopDown,
    IERC998ERC20TopDownEnumerable
{
    using Address for address;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;
    // return this.rootOwnerOf.selector ^ this.rootOwnerOfChild.selector ^
    //   this.tokenOwnerOf.selector ^ this.ownerOfChild.selector;
    bytes4 constant ERC998_MAGIC_VALUE = 0xcd740db5;

    uint256 tokenCount = 0;

    // tokenId => token owner
    mapping(uint256 => address) internal tokenIdToTokenOwner;

    // root token owner address => (tokenId => approved address)
    mapping(address => mapping(uint256 => address))
        internal rootOwnerAndTokenIdToApprovedAddress;

    // token owner address => token count
    mapping(address => uint256) internal tokenOwnerToTokenCount;

    // token owner => (operator address => bool)
    mapping(address => mapping(address => bool)) internal tokenOwnerToOperators;

    //constructor(string _name, string _symbol) public ERC721Token(_name, _symbol) {}

    // wrapper on minting new 721
    // @notice Be cautious when minting to contracts
    function mint(address _to) public returns (uint256) {
        tokenCount++;
        uint256 tokenCount_ = tokenCount;
        tokenIdToTokenOwner[tokenCount_] = _to;
        tokenOwnerToTokenCount[_to]++;
        return tokenCount_;
    }

    //from zepellin ERC721Receiver.sol
    //old version
    bytes4 constant ERC721_RECEIVED_OLD = 0xf0b9e5ba;
    //new version
    bytes4 constant ERC721_RECEIVED_NEW = 0x150b7a02;

    bytes4 constant ALLOWANCE = bytes4(keccak256("allowance(address,address)"));
    bytes4 constant APPROVE = bytes4(keccak256("approve(address,uint256)"));
    bytes4 constant ROOT_OWNER_OF_CHILD =
        bytes4(keccak256("rootOwnerOfChild(address,uint256)"));

    ////////////////////////////////////////////////////////
    // ERC721 implementation
    ////////////////////////////////////////////////////////
    function rootOwnerOf(uint256 _tokenId)
        public
        view
        override
        returns (bytes32 rootOwner)
    {
        return rootOwnerOfChild(address(0), _tokenId);
    }

    // returns the owner at the top of the tree of composables
    // Use Cases handled:
    // Case 1: Token owner is this contract and token.
    // Case 2: Token owner is other top-down composable
    // Case 3: Token owner is other contract
    // Case 4: Token owner is user
    function rootOwnerOfChild(address _childContract, uint256 _childTokenId)
        public
        view
        override
        returns (bytes32 rootOwner)
    {
        address rootOwnerAddress;
        if (_childContract != address(0)) {
            (rootOwnerAddress, _childTokenId) = _ownerOfChild(
                _childContract,
                _childTokenId
            );
        } else {
            rootOwnerAddress = tokenIdToTokenOwner[_childTokenId];
        }
        // Case 1: Token owner is this contract and token.
        while (rootOwnerAddress == address(this)) {
            (rootOwnerAddress, _childTokenId) = _ownerOfChild(
                rootOwnerAddress,
                _childTokenId
            );
        }
        bytes memory callData =
            abi.encodeWithSelector(
                ROOT_OWNER_OF_CHILD,
                address(this),
                _childTokenId
            );
        (bool callSuccess, bytes memory data) =
            rootOwnerAddress.staticcall(callData);
        if (callSuccess) {
            assembly {
                rootOwner := mload(add(data, 0x20))
            }
        }

        if (callSuccess == true && rootOwner >> 224 == ERC998_MAGIC_VALUE) {
            // Case 2: Token owner is other top-down composable
            return rootOwner;
        } else {
            // Case 3: Token owner is other contract
            // Or
            // Case 4: Token owner is user
            return
                (ERC998_MAGIC_VALUE << 224) |
                bytes32(uint256(uint160(rootOwnerAddress)));
        }
    }

    // returns the owner at the top of the tree of composables

    function ownerOf(uint256 _tokenId)
        public
        view
        override
        returns (address tokenOwner)
    {
        tokenOwner = tokenIdToTokenOwner[_tokenId];
        require(
            tokenOwner != address(0),
            "ComposableTopDown: ownerOf _tokenId zero address"
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
            "ComposableTopDown: balanceOf _tokenOwner zero address"
        );
        return tokenOwnerToTokenCount[_tokenOwner];
    }

    function approve(address _approved, uint256 _tokenId) external override {
        address rootOwner = address(uint160(uint256(rootOwnerOf(_tokenId))));
        require(
            rootOwner == msg.sender ||
                tokenOwnerToOperators[rootOwner][msg.sender],
            "ComposableTopDown: approve msg.sender not owner"
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
        require(
            _operator != address(0),
            "ComposableTopDown: setApprovalForAll _operator zero address"
        );
        tokenOwnerToOperators[msg.sender][_operator] = _approved;
        emit ApprovalForAll(msg.sender, _operator, _approved);
    }

    function isApprovedForAll(address _owner, address _operator)
        external
        view
        override
        returns (bool)
    {
        require(
            _owner != address(0),
            "ComposableTopDown: isApprovedForAll _owner zero address"
        );
        require(
            _operator != address(0),
            "ComposableTopDown: isApprovedForAll _operator zero address"
        );
        return tokenOwnerToOperators[_owner][_operator];
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
        if (_to.isContract()) {
            bytes4 retval =
                IERC721Receiver(_to).onERC721Received(
                    msg.sender,
                    _from,
                    _tokenId,
                    ""
                );
            require(
                retval == ERC721_RECEIVED_OLD || retval == ERC721_RECEIVED_NEW,
                "ComposableTopDown: safeTransferFrom(3) onERC721Received invalid return value"
            );
        }
    }

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        bytes memory _data
    ) external override {
        _transferFrom(_from, _to, _tokenId);
        if (_to.isContract()) {
            bytes4 retval =
                IERC721Receiver(_to).onERC721Received(
                    msg.sender,
                    _from,
                    _tokenId,
                    _data
                );
            require(
                retval == ERC721_RECEIVED_OLD || retval == ERC721_RECEIVED_NEW,
                "ComposableTopDown: safeTransferFrom(4) onERC721Received invalid return value"
            );
        }
    }

    function _transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) private {
        require(
            _from != address(0),
            "ComposableTopDown: _transferFrom _from zero address"
        );
        require(
            tokenIdToTokenOwner[_tokenId] == _from,
            "ComposableTopDown: _transferFrom _from not owner"
        );
        require(
            _to != address(0),
            "ComposableTopDown: _transferFrom _to zero address"
        );

        if (msg.sender != _from) {
            bytes memory callData =
                abi.encodeWithSelector(
                    ROOT_OWNER_OF_CHILD,
                    address(this),
                    _tokenId
                );
            (bool callSuccess, bytes memory data) = _from.staticcall(callData);
            if (callSuccess == true) {
                bytes32 rootOwner;
                assembly {
                    rootOwner := mload(add(data, 0x20))
                }
                require(
                    rootOwner >> 224 != ERC998_MAGIC_VALUE,
                    "ComposableTopDown: _transferFrom token is child of other top down composable"
                );
            }

            require(
                tokenOwnerToOperators[_from][msg.sender] ||
                    rootOwnerAndTokenIdToApprovedAddress[_from][_tokenId] ==
                    msg.sender,
                "ComposableTopDown: _transferFrom msg.sender not approved"
            );
        }

        // clear approval
        if (
            rootOwnerAndTokenIdToApprovedAddress[_from][_tokenId] != address(0)
        ) {
            delete rootOwnerAndTokenIdToApprovedAddress[_from][_tokenId];
            emit Approval(_from, address(0), _tokenId);
        }

        // remove and transfer token
        if (_from != _to) {
            assert(tokenOwnerToTokenCount[_from] > 0);
            tokenOwnerToTokenCount[_from]--;
            tokenIdToTokenOwner[_tokenId] = _to;
            tokenOwnerToTokenCount[_to]++;
        }
        emit Transfer(_from, _to, _tokenId);
    }

    ////////////////////////////////////////////////////////
    // ERC998ERC721 and ERC998ERC721Enumerable implementation
    ////////////////////////////////////////////////////////

    // tokenId => child contract
    mapping(uint256 => EnumerableSet.AddressSet) private childContracts;

    // tokenId => (child address => array of child tokens)
    mapping(uint256 => mapping(address => EnumerableSet.UintSet))
        private childTokens;

    // child address => childId => tokenId
    mapping(address => mapping(uint256 => uint256)) internal childTokenOwner;

    function safeTransferChild(
        uint256 _fromTokenId,
        address _to,
        address _childContract,
        uint256 _childTokenId
    ) external override {
        _transferChild(_fromTokenId, _to, _childContract, _childTokenId);
        IERC721(_childContract).safeTransferFrom(
            address(this),
            _to,
            _childTokenId
        );
        emit TransferChild(_fromTokenId, _to, _childContract, _childTokenId);
    }

    function safeTransferChild(
        uint256 _fromTokenId,
        address _to,
        address _childContract,
        uint256 _childTokenId,
        bytes memory _data
    ) external override {
        _transferChild(_fromTokenId, _to, _childContract, _childTokenId);
        IERC721(_childContract).safeTransferFrom(
            address(this),
            _to,
            _childTokenId,
            _data
        );
        emit TransferChild(_fromTokenId, _to, _childContract, _childTokenId);
    }

    function transferChild(
        uint256 _fromTokenId,
        address _to,
        address _childContract,
        uint256 _childTokenId
    ) external override {
        _transferChild(_fromTokenId, _to, _childContract, _childTokenId);
        //this is here to be compatible with cryptokitties and other old contracts that require being owner and approved
        // before transferring.
        //does not work with current standard which does not allow approving self, so we must let it fail in that case.
        bytes memory callData =
            abi.encodeWithSelector(APPROVE, this, _childTokenId);
        (bool callSuccess, bytes memory data) = _childContract.call(callData);

        IERC721(_childContract).transferFrom(address(this), _to, _childTokenId);
        emit TransferChild(_fromTokenId, _to, _childContract, _childTokenId);
    }

    function transferChildToParent(
        uint256 _fromTokenId,
        address _toContract,
        uint256 _toTokenId,
        address _childContract,
        uint256 _childTokenId,
        bytes memory _data
    ) external override {
        _transferChild(
            _fromTokenId,
            _toContract,
            _childContract,
            _childTokenId
        );
        IERC998ERC721BottomUp(_childContract).transferToParent(
            address(this),
            _toContract,
            _toTokenId,
            _childTokenId,
            _data
        );
        emit TransferChild(
            _fromTokenId,
            _toContract,
            _childContract,
            _childTokenId
        );
    }

    // this contract has to be approved first in _childContract
    function getChild(
        address _from,
        uint256 _tokenId,
        address _childContract,
        uint256 _childTokenId
    ) external override {
        receiveChild(_from, _tokenId, _childContract, _childTokenId);
        require(
            _from == msg.sender ||
                IERC721(_childContract).isApprovedForAll(_from, msg.sender) ||
                IERC721(_childContract).getApproved(_childTokenId) ==
                msg.sender,
            "ComposableTopDown: getChild msg.sender not approved"
        );
        IERC721(_childContract).transferFrom(
            _from,
            address(this),
            _childTokenId
        );
    }

    function onERC721Received(
        address _from,
        uint256 _childTokenId,
        bytes calldata _data
    ) external returns (bytes4) {
        require(
            _data.length > 0,
            "ComposableTopDown: onERC721Received(3) _data must contain the uint256 tokenId to transfer the child token to"
        );
        // convert up to 32 bytes of _data to uint256, owner nft tokenId passed as uint in bytes
        uint256 tokenId = _parseTokenId(_data, 132);
        receiveChild(_from, tokenId, msg.sender, _childTokenId);
        require(
            IERC721(msg.sender).ownerOf(_childTokenId) != address(0),
            "ComposableTopDown: onERC721Received(3) child token not owned"
        );
        return ERC721_RECEIVED_OLD;
    }

    function onERC721Received(
        address,
        address _from,
        uint256 _childTokenId,
        bytes calldata _data
    ) external override returns (bytes4) {
        require(
            _data.length > 0,
            "ComposableTopDown: onERC721Received(4) _data must contain the uint256 tokenId to transfer the child token to"
        );
        // convert up to 32 bytes of _data to uint256, owner nft tokenId passed as uint in bytes
        uint256 tokenId = _parseTokenId(_data, 164);
        receiveChild(_from, tokenId, msg.sender, _childTokenId);
        require(
            IERC721(msg.sender).ownerOf(_childTokenId) != address(0),
            "ComposableTopDown: onERC721Received(4) child token not owned"
        );
        return ERC721_RECEIVED_NEW;
    }

    function childExists(address _childContract, uint256 _childTokenId)
        external
        view
        returns (bool)
    {
        uint256 tokenId = childTokenOwner[_childContract][_childTokenId];
        return childTokens[tokenId][_childContract].contains(_childTokenId);
    }

    function totalChildContracts(uint256 _tokenId)
        external
        view
        override
        returns (uint256)
    {
        return childContracts[_tokenId].length();
    }

    function childContractByIndex(uint256 _tokenId, uint256 _index)
        external
        view
        override
        returns (address childContract)
    {
        return childContracts[_tokenId].at(_index);
    }

    function totalChildTokens(uint256 _tokenId, address _childContract)
        external
        view
        override
        returns (uint256)
    {
        return childTokens[_tokenId][_childContract].length();
    }

    function childTokenByIndex(
        uint256 _tokenId,
        address _childContract,
        uint256 _index
    ) external view override returns (uint256 childTokenId) {
        return childTokens[_tokenId][_childContract].at(_index);
    }

    function ownerOfChild(address _childContract, uint256 _childTokenId)
        external
        view
        override
        returns (bytes32 parentTokenOwner, uint256 parentTokenId)
    {
        parentTokenId = childTokenOwner[_childContract][_childTokenId];
        require(
            parentTokenId > 0 ||
                childTokens[parentTokenId][_childContract].contains(
                    _childTokenId
                ),
            "ComposableTopDown: ownerOfChild not found"
        );
        return (
            (ERC998_MAGIC_VALUE << 224) |
                bytes32(uint256(uint160(tokenIdToTokenOwner[parentTokenId]))),
            parentTokenId
        );
    }

    function _transferChild(
        uint256 _fromTokenId,
        address _to,
        address _childContract,
        uint256 _childTokenId
    ) internal {
        uint256 tokenId = childTokenOwner[_childContract][_childTokenId];
        require(
            tokenId > 0 ||
                childTokens[tokenId][_childContract].contains(_childTokenId),
            "ComposableTopDown: _transferChild _childContract _childTokenId not found"
        );
        require(
            tokenId == _fromTokenId,
            "ComposableTopDown: _transferChild wrong tokenId found"
        );
        require(
            _to != address(0),
            "ComposableTopDown: _transferChild _to zero address"
        );
        address rootOwner = address(uint160(uint256(rootOwnerOf(tokenId))));
        require(
            rootOwner == msg.sender ||
                tokenOwnerToOperators[rootOwner][msg.sender] ||
                rootOwnerAndTokenIdToApprovedAddress[rootOwner][tokenId] ==
                msg.sender,
            "ComposableTopDown: _transferChild msg.sender not eligible"
        );
        removeChild(tokenId, _childContract, _childTokenId);
    }

    function _ownerOfChild(address _childContract, uint256 _childTokenId)
        internal
        view
        returns (address parentTokenOwner, uint256 parentTokenId)
    {
        parentTokenId = childTokenOwner[_childContract][_childTokenId];
        require(
            parentTokenId > 0 ||
                childTokens[parentTokenId][_childContract].contains(
                    _childTokenId
                ),
            "ComposableTopDown: _ownerOfChild not found"
        );
        return (tokenIdToTokenOwner[parentTokenId], parentTokenId);
    }

    function _parseTokenId(bytes memory _data, uint256 _position)
        internal
        pure
        returns (uint256)
    {
        // convert up to 32 bytes of_data to uint256, owner nft tokenId passed as uint in bytes
        uint256 tokenId;
        assembly {
            tokenId := calldataload(_position)
        }
        if (_data.length < 32) {
            tokenId = tokenId >> (256 - _data.length * 8);
        }

        return tokenId;
    }

    function removeChild(
        uint256 _tokenId,
        address _childContract,
        uint256 _childTokenId
    ) private {
        // remove child token
        uint256 lastTokenIndex =
            childTokens[_tokenId][_childContract].length() - 1;
        childTokens[_tokenId][_childContract].remove(_childTokenId);
        delete childTokenOwner[_childContract][_childTokenId];

        // remove contract
        if (lastTokenIndex == 0) {
            childContracts[_tokenId].remove(_childContract);
        }
    }

    function receiveChild(
        address _from,
        uint256 _tokenId,
        address _childContract,
        uint256 _childTokenId
    ) private {
        require(
            tokenIdToTokenOwner[_tokenId] != address(0),
            "ComposableTopDown: receiveChild _tokenId does not exist."
        );
        require(
            !childTokens[_tokenId][_childContract].contains(_childTokenId),
            "ComposableTopDown: receiveChild _childTokenId already received"
        );
        uint256 childTokensLength =
            childTokens[_tokenId][_childContract].length();
        if (childTokensLength == 0) {
            childContracts[_tokenId].add(_childContract);
        }
        childTokens[_tokenId][_childContract].add(_childTokenId);
        childTokenOwner[_childContract][_childTokenId] = _tokenId;
        emit ReceivedChild(_from, _tokenId, _childContract, _childTokenId);
    }

    ////////////////////////////////////////////////////////
    // ERC998ERC223 and ERC998ERC223Enumerable implementation
    ////////////////////////////////////////////////////////

    // tokenId => token contract
    mapping(uint256 => EnumerableSet.AddressSet) erc20Contracts;

    // tokenId => (token contract => balance)
    mapping(uint256 => mapping(address => uint256)) erc20Balances;

    function transferERC20(
        uint256 _tokenId,
        address _to,
        address _erc20Contract,
        uint256 _value
    ) external override {
        require(
            _to != address(0),
            "ComposableTopDown: transferERC20 _to zero address"
        );
        address rootOwner = address(uint160(uint256(rootOwnerOf(_tokenId))));
        require(
            rootOwner == msg.sender ||
                tokenOwnerToOperators[rootOwner][msg.sender] ||
                rootOwnerAndTokenIdToApprovedAddress[rootOwner][_tokenId] ==
                msg.sender,
            "ComposableTopDown: transferERC20 msg.sender not eligible"
        );
        removeERC20(_tokenId, _erc20Contract, _value);
        require(
            IERC20AndERC223(_erc20Contract).transfer(_to, _value),
            "ComposableTopDown: transferERC20 transfer failed"
        );
        emit TransferERC20(_tokenId, _to, _erc20Contract, _value);
    }

    // implementation of ERC 223
    function transferERC223(
        uint256 _tokenId,
        address _to,
        address _erc223Contract,
        uint256 _value,
        bytes memory _data
    ) external override {
        require(
            _to != address(0),
            "ComposableTopDown: transferERC223 _to zero address"
        );
        address rootOwner = address(uint160(uint256(rootOwnerOf(_tokenId))));
        require(
            rootOwner == msg.sender ||
                tokenOwnerToOperators[rootOwner][msg.sender] ||
                rootOwnerAndTokenIdToApprovedAddress[rootOwner][_tokenId] ==
                msg.sender,
            "ComposableTopDown: transferERC223 msg.sender not eligible"
        );
        removeERC20(_tokenId, _erc223Contract, _value);
        require(
            IERC20AndERC223(_erc223Contract).transfer(_to, _value, _data),
            "ComposableTopDown: transferERC223 transfer failed"
        );
        emit TransferERC20(_tokenId, _to, _erc223Contract, _value);
    }

    // used by ERC 223
    function tokenFallback(
        address _from,
        uint256 _value,
        bytes memory _data
    ) external override {
        require(
            _data.length > 0,
            "ComposableTopDown: tokenFallback _data must contain the uint256 tokenId to transfer the token to"
        );
        require(
            address(msg.sender).isContract(),
            "ComposableTopDown: tokenFallback msg.sender is not a contract"
        );
        uint256 tokenId = _parseTokenId(_data, 132);
        erc20Received(_from, tokenId, msg.sender, _value);
    }

    function balanceOfERC20(uint256 _tokenId, address _erc20Contract)
        external
        view
        override
        returns (uint256)
    {
        return erc20Balances[_tokenId][_erc20Contract];
    }

    function erc20ContractByIndex(uint256 _tokenId, uint256 _index)
        external
        view
        override
        returns (address)
    {
        return erc20Contracts[_tokenId].at(_index);
    }

    function totalERC20Contracts(uint256 _tokenId)
        external
        view
        override
        returns (uint256)
    {
        return erc20Contracts[_tokenId].length();
    }

    // this contract has to be approved first by _erc20Contract
    function getERC20(
        address _from,
        uint256 _tokenId,
        address _erc20Contract,
        uint256 _value
    ) public override {
        bool allowed = _from == msg.sender;
        if (!allowed) {
            bytes memory callData =
                abi.encodeWithSelector(ALLOWANCE, _from, msg.sender);
            (bool callSuccess, bytes memory data) =
                _erc20Contract.staticcall(callData);
            require(
                callSuccess,
                "ComposableTopDown: getERC20 allowance failed"
            );
            uint256 remaining;
            assembly {
                remaining := mload(add(data, 0x20))
            }
            require(
                remaining >= _value,
                "ComposableTopDown: getERC20 value greater than remaining"
            );
            allowed = true;
        }
        require(allowed, "ComposableTopDown: getERC20 not allowed to getERC20");
        erc20Received(_from, _tokenId, _erc20Contract, _value);
        require(
            IERC20AndERC223(_erc20Contract).transferFrom(
                _from,
                address(this),
                _value
            ),
            "ComposableTopDown: getERC20 transfer failed"
        );
    }

    function erc20Received(
        address _from,
        uint256 _tokenId,
        address _erc20Contract,
        uint256 _value
    ) private {
        require(
            tokenIdToTokenOwner[_tokenId] != address(0),
            "ComposableTopDown: erc20Received _tokenId does not exist"
        );
        if (_value == 0) {
            return;
        }
        uint256 erc20Balance = erc20Balances[_tokenId][_erc20Contract];
        if (erc20Balance == 0) {
            erc20Contracts[_tokenId].add(_erc20Contract);
        }
        erc20Balances[_tokenId][_erc20Contract] += _value;
        emit ReceivedERC20(_from, _tokenId, _erc20Contract, _value);
    }

    function removeERC20(
        uint256 _tokenId,
        address _erc20Contract,
        uint256 _value
    ) private {
        if (_value == 0) {
            return;
        }
        uint256 erc20Balance = erc20Balances[_tokenId][_erc20Contract];
        require(
            erc20Balance >= _value,
            "ComposableTopDown: removeERC20 value not enough"
        );
        uint256 newERC20Balance = erc20Balance - _value;
        erc20Balances[_tokenId][_erc20Contract] = newERC20Balance;
        if (newERC20Balance == 0) {
            erc20Contracts[_tokenId].remove(_erc20Contract);
        }
    }
}
