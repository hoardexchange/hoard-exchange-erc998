pragma solidity ^0.7.0;

import "@openzeppelin/contracts/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
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

    ////////////////////////////////////////////////////////
    // ERC721 implementation
    ////////////////////////////////////////////////////////

    function isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }

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
            abi.encodeWithSelector(0xed81cdda, address(this), _childTokenId);
        // 0xed81cdda == rootOwnerOfChild(address,uint256)
        (bool callSuccess, bytes memory data) =
            rootOwnerAddress.staticcall(callData);
        if (callSuccess) {
            rootOwner = abi.decode(data, (bytes32));
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
        require(tokenOwner != address(0));
        return tokenOwner;
    }

    function balanceOf(address _tokenOwner)
        external
        view
        override
        returns (uint256)
    {
        require(_tokenOwner != address(0));
        return tokenOwnerToTokenCount[_tokenOwner];
    }

    function approve(address _approved, uint256 _tokenId) external override {
        address rootOwner = address(uint160(uint256(rootOwnerOf(_tokenId))));
        require(
            rootOwner == msg.sender ||
                tokenOwnerToOperators[rootOwner][msg.sender]
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
        require(_operator != address(0));
        tokenOwnerToOperators[msg.sender][_operator] = _approved;
        emit ApprovalForAll(msg.sender, _operator, _approved);
    }

    function isApprovedForAll(address _owner, address _operator)
        external
        view
        override
        returns (bool)
    {
        require(_owner != address(0));
        require(_operator != address(0));
        return tokenOwnerToOperators[_owner][_operator];
    }

    function _transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) private {
        require(_from != address(0));
        require(tokenIdToTokenOwner[_tokenId] == _from);
        require(_to != address(0));

        if (msg.sender != _from) {
            // 0xed81cdda == rootOwnerOfChild(address,uint256)
            bytes memory callData =
                abi.encodeWithSelector(0xed81cdda, address(this), _tokenId);
            (bool callSuccess, bytes memory data) = _from.staticcall(callData);
            if (callSuccess == true) {
                bytes32 rootOwner = abi.decode(data, (bytes32));
                require(
                    rootOwner >> 224 != ERC998_MAGIC_VALUE,
                    "Token is child of other top down composable"
                );
            }

            require(
                tokenOwnerToOperators[_from][msg.sender] ||
                    rootOwnerAndTokenIdToApprovedAddress[_from][_tokenId] ==
                    msg.sender
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
            require(retval == ERC721_RECEIVED_OLD);
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
            require(retval == ERC721_RECEIVED_OLD);
        }
    }

    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;
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

    function safeTransferChild(
        uint256 _fromTokenId,
        address _to,
        address _childContract,
        uint256 _childTokenId
    ) external override {
        uint256 tokenId = childTokenOwner[_childContract][_childTokenId];
        require(
            tokenId > 0 ||
                childTokens[tokenId][_childContract].contains(_childTokenId)
        );
        require(tokenId == _fromTokenId);
        require(_to != address(0));
        address rootOwner = address(uint160(uint256(rootOwnerOf(tokenId))));
        require(
            rootOwner == msg.sender ||
                tokenOwnerToOperators[rootOwner][msg.sender] ||
                rootOwnerAndTokenIdToApprovedAddress[rootOwner][tokenId] ==
                msg.sender
        );
        removeChild(tokenId, _childContract, _childTokenId);
        IERC721(_childContract).safeTransferFrom(
            address(this),
            _to,
            _childTokenId
        );
        emit TransferChild(tokenId, _to, _childContract, _childTokenId);
    }

    function safeTransferChild(
        uint256 _fromTokenId,
        address _to,
        address _childContract,
        uint256 _childTokenId,
        bytes memory _data
    ) external override {
        uint256 tokenId = childTokenOwner[_childContract][_childTokenId];
        require(
            tokenId > 0 ||
                childTokens[tokenId][_childContract].contains(_childTokenId)
        );
        require(tokenId == _fromTokenId);
        require(_to != address(0));
        address rootOwner = address(uint160(uint256(rootOwnerOf(tokenId))));
        require(
            rootOwner == msg.sender ||
                tokenOwnerToOperators[rootOwner][msg.sender] ||
                rootOwnerAndTokenIdToApprovedAddress[rootOwner][tokenId] ==
                msg.sender
        );
        removeChild(tokenId, _childContract, _childTokenId);
        IERC721(_childContract).safeTransferFrom(
            address(this),
            _to,
            _childTokenId,
            _data
        );
        emit TransferChild(tokenId, _to, _childContract, _childTokenId);
    }

    function transferChild(
        uint256 _fromTokenId,
        address _to,
        address _childContract,
        uint256 _childTokenId
    ) external override {
        uint256 tokenId = childTokenOwner[_childContract][_childTokenId];
        require(
            tokenId > 0 ||
                childTokens[tokenId][_childContract].contains(_childTokenId)
        );
        require(tokenId == _fromTokenId);
        require(_to != address(0));
        address rootOwner = address(uint160(uint256(rootOwnerOf(tokenId))));
        require(
            rootOwner == msg.sender ||
                tokenOwnerToOperators[rootOwner][msg.sender] ||
                rootOwnerAndTokenIdToApprovedAddress[rootOwner][tokenId] ==
                msg.sender
        );
        removeChild(tokenId, _childContract, _childTokenId);
        //this is here to be compatible with cryptokitties and other old contracts that require being owner and approved
        // before transferring.
        //does not work with current standard which does not allow approving self, so we must let it fail in that case.
        //0x095ea7b3 == "approve(address,uint256)"
        bytes memory callData =
            abi.encodeWithSelector(0x095ea7b3, this, _childTokenId);
        (bool callSuccess, bytes memory data) = _childContract.call(callData);
        require(
            callSuccess == true &&
                (data.length == 0 || abi.decode(data, (bool))),
            "failed to approve"
        );

        IERC721(_childContract).transferFrom(address(this), _to, _childTokenId);
        emit TransferChild(tokenId, _to, _childContract, _childTokenId);
    }

    function transferChildToParent(
        uint256 _fromTokenId,
        address _toContract,
        uint256 _toTokenId,
        address _childContract,
        uint256 _childTokenId,
        bytes memory _data
    ) external override {
        uint256 tokenId = childTokenOwner[_childContract][_childTokenId];
        require(
            tokenId > 0 ||
                childTokens[tokenId][_childContract].contains(_childTokenId)
        );
        require(tokenId == _fromTokenId);
        require(_toContract != address(0));
        address rootOwner = address(uint160(uint256(rootOwnerOf(tokenId))));
        require(
            rootOwner == msg.sender ||
                tokenOwnerToOperators[rootOwner][msg.sender] ||
                rootOwnerAndTokenIdToApprovedAddress[rootOwner][tokenId] ==
                msg.sender
        );
        removeChild(_fromTokenId, _childContract, _childTokenId);
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
                IERC721(_childContract).getApproved(_childTokenId) == msg.sender
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
        bytes memory _data
    ) external returns (bytes4) {
        require(
            _data.length > 0,
            "_data must contain the uint256 tokenId to transfer the child token to."
        );
        // convert up to 32 bytes of_data to uint256, owner nft tokenId passed as uint in bytes
        uint256 tokenId;
        assembly {
            tokenId := calldataload(132)
        }
        if (_data.length < 32) {
            tokenId = tokenId >> (256 - _data.length * 8);
        }
        receiveChild(_from, tokenId, msg.sender, _childTokenId);
        require(
            IERC721(msg.sender).ownerOf(_childTokenId) != address(0),
            "Child token not owned."
        );
        return ERC721_RECEIVED_OLD;
    }

    function onERC721Received(
        address _operator,
        address _from,
        uint256 _childTokenId,
        bytes memory _data
    ) external override returns (bytes4) {
        require(
            _data.length > 0,
            "_data must contain the uint256 tokenId to transfer the child token to."
        );
        // convert up to 32 bytes of_data to uint256, owner nft tokenId passed as uint in bytes
        uint256 tokenId;
        assembly {
            tokenId := calldataload(164)
        }
        if (_data.length < 32) {
            tokenId = tokenId >> (256 - _data.length * 8);
        }
        receiveChild(_from, tokenId, msg.sender, _childTokenId);
        require(
            IERC721(msg.sender).ownerOf(_childTokenId) != address(0),
            "Child token not owned."
        );
        return ERC721_RECEIVED_NEW;
    }

    function receiveChild(
        address _from,
        uint256 _tokenId,
        address _childContract,
        uint256 _childTokenId
    ) private {
        require(
            tokenIdToTokenOwner[_tokenId] != address(0),
            "_tokenId does not exist."
        );
        require(
            !childTokens[_tokenId][_childContract].contains(_childTokenId),
            "Cannot receive child token because it has already been received."
        );
        childTokens[_tokenId][_childContract].add(_childTokenId);
        childTokenOwner[_childContract][_childTokenId] = _tokenId;
        emit ReceivedChild(_from, _tokenId, _childContract, _childTokenId);
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
                )
        );
        return (tokenIdToTokenOwner[parentTokenId], parentTokenId);
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
                )
        );
        return (
            (ERC998_MAGIC_VALUE << 224) |
                bytes32(uint256(uint160(tokenIdToTokenOwner[parentTokenId]))),
            parentTokenId
        );
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

    ////////////////////////////////////////////////////////
    // ERC998ERC223 and ERC998ERC223Enumerable implementation
    ////////////////////////////////////////////////////////

    using EnumerableSet for EnumerableSet.AddressSet;

    // tokenId => token contract
    mapping(uint256 => EnumerableSet.AddressSet) erc20Contracts;

    // tokenId => (token contract => balance)
    mapping(uint256 => mapping(address => uint256)) erc20Balances;

    function balanceOfERC20(uint256 _tokenId, address _erc20Contract)
        external
        view
        override
        returns (uint256)
    {
        return erc20Balances[_tokenId][_erc20Contract];
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
            "Not enough token available to transfer."
        );
        uint256 newERC20Balance = erc20Balance - _value;
        erc20Balances[_tokenId][_erc20Contract] = newERC20Balance;
        if (newERC20Balance == 0) {
            erc20Contracts[_tokenId].remove(_erc20Contract);
        }
    }

    function transferERC20(
        uint256 _tokenId,
        address _to,
        address _erc20Contract,
        uint256 _value
    ) external override {
        require(_to != address(0));
        address rootOwner = address(uint160(uint256(rootOwnerOf(_tokenId))));
        require(
            rootOwner == msg.sender ||
                tokenOwnerToOperators[rootOwner][msg.sender] ||
                rootOwnerAndTokenIdToApprovedAddress[rootOwner][_tokenId] ==
                msg.sender
        );
        removeERC20(_tokenId, _erc20Contract, _value);
        require(
            IERC20AndERC223(_erc20Contract).transfer(_to, _value),
            "ERC20 transfer failed."
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
        require(_to != address(0));
        address rootOwner = address(uint160(uint256(rootOwnerOf(_tokenId))));
        require(
            rootOwner == msg.sender ||
                tokenOwnerToOperators[rootOwner][msg.sender] ||
                rootOwnerAndTokenIdToApprovedAddress[rootOwner][_tokenId] ==
                msg.sender
        );
        removeERC20(_tokenId, _erc223Contract, _value);
        require(
            IERC20AndERC223(_erc223Contract).transfer(_to, _value, _data),
            "ERC223 transfer failed."
        );
        emit TransferERC20(_tokenId, _to, _erc223Contract, _value);
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
            // 0xdd62ed3e == allowance(address,address)
            bytes memory callData =
                abi.encodeWithSelector(0xdd62ed3e, _from, msg.sender);
            (bool callSuccess, bytes memory data) =
                _erc20Contract.staticcall(callData);
            require(callSuccess, "call to allowance failed");
            uint256 remaining = abi.decode(data, (uint256));
            require(remaining >= _value, "Value greater than remaining");
            allowed = true;
        }
        require(allowed, "not allowed to getERC20");
        erc20Received(_from, _tokenId, _erc20Contract, _value);
        require(
            IERC20AndERC223(_erc20Contract).transferFrom(
                _from,
                address(this),
                _value
            ),
            "ERC20 transfer failed."
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
            "_tokenId does not exist."
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

    // used by ERC 223
    function tokenFallback(
        address _from,
        uint256 _value,
        bytes memory _data
    ) external override {
        require(
            _data.length > 0,
            "_data must contain the uint256 tokenId to transfer the token to."
        );
        require(isContract(msg.sender), "msg.sender is not a contract");
        /**************************************
         * TODO move to library
         **************************************/
        // convert up to 32 bytes of_data to uint256, owner nft tokenId passed as uint in bytes
        uint256 tokenId;
        assembly {
            tokenId := calldataload(132)
        }
        if (_data.length < 32) {
            tokenId = tokenId >> (256 - _data.length * 8);
        }
        //END TODO
        erc20Received(_from, tokenId, msg.sender, _value);
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
}
