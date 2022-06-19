const { assert, expect } = require('chai');
const { ethers } = require("hardhat");

describe('ComposableTopDownERC1155', async () => {
    let ComposableTopDown,
        SampleERC1155;

    const expectedTokenId = 1;
    const firstChildTokenId = 1;
    const aliceBalance = 1;

    const bytesFirstToken = ethers.utils.hexZeroPad('0x1', 20);
    const zeroAddress = ethers.utils.hexZeroPad('0x0', 20);
    const ERC998_MAGIC_VALUE = '0xcd740db5';

    const NFTHash = '0x1234';

    beforeEach(async () => {
        [
            alice,
            bob,
            owner,
            nonUsed,
        ] = await ethers.getSigners();
        aliceBytes32Address = ethers.utils.hexConcat([ERC998_MAGIC_VALUE, ethers.utils.hexZeroPad(alice.address, 28).toLowerCase()]);

        ComposableTopDown = await ethers.getContractFactory("ComposableTopDownERC1155Dev");
        SampleERC1155 = await ethers.getContractFactory("SampleERC1155");

        composableTopDownInstance = await ComposableTopDown.deploy();
        await composableTopDownInstance.deployed();
    });


    describe('ERC1155 Transfers', async () => {
        const uri = 'https://token-cdn-domain/\\{id\\}.json';

        beforeEach(async () => {
            sampleERC1155Instance = await SampleERC1155.deploy(uri);

            // mint
            await sampleERC1155Instance.mint(alice.address, 1, 10);
            await sampleERC1155Instance.mint(alice.address, 2, 10);
            await sampleERC1155Instance.mint(alice.address, 3, 10);

            await composableTopDownInstance.safeMint(alice.address);

            sampleERC1155InstanceAlice = sampleERC1155Instance.connect(alice);
        });

        function arrayEq(a, b) {
            if (a.length != b.length) {
                return false;
            }
            for (i = 0 ; i < a.length ; i ++) {
                if (! a[i].eq(b[i])) {
                    return false;
                }
            }
            return true;
        }

        it('Should transfer single', async () => {
            await sampleERC1155InstanceAlice.safeTransferFrom(alice.address, composableTopDownInstance.address, 1, 1, bytesFirstToken);
            assert((await composableTopDownInstance.balanceOfERC1155(1, sampleERC1155Instance.address, 1)).eq(1), 'Invalid single token balance (1)');
            await sampleERC1155InstanceAlice.safeTransferFrom(alice.address, composableTopDownInstance.address, 1, 5, bytesFirstToken);
            assert((await composableTopDownInstance.balanceOfERC1155(1, sampleERC1155Instance.address, 1)).eq(6), 'Invalid single token balance (2)');
            await composableTopDownInstance.safeTransferFromERC1155(1, alice.address, sampleERC1155InstanceAlice.address, 1, 4, bytesFirstToken);
            assert((await composableTopDownInstance.balanceOfERC1155(1, sampleERC1155Instance.address, 1)).eq(2), 'Invalid single token balance (3)');
        });

        it('Should transfer multiple', async () => {
            await sampleERC1155InstanceAlice.safeTransferFrom(alice.address, composableTopDownInstance.address, 1, 3, bytesFirstToken);
            await sampleERC1155InstanceAlice.safeTransferFrom(alice.address, composableTopDownInstance.address, 2, 6, bytesFirstToken);
            await sampleERC1155InstanceAlice.safeTransferFrom(alice.address, composableTopDownInstance.address, 3, 9, bytesFirstToken);
            await composableTopDownInstance.safeTransferFromERC1155(1, alice.address, sampleERC1155InstanceAlice.address, 1, 1, bytesFirstToken);
            await composableTopDownInstance.safeTransferFromERC1155(1, alice.address, sampleERC1155InstanceAlice.address, 2, 2, bytesFirstToken);
            await composableTopDownInstance.safeTransferFromERC1155(1, alice.address, sampleERC1155InstanceAlice.address, 3, 3, bytesFirstToken);
            assert((await composableTopDownInstance.balanceOfERC1155(1, sampleERC1155Instance.address, 1)).eq(2), 'Invalid multiple token balance (1)');
            assert((await composableTopDownInstance.balanceOfERC1155(1, sampleERC1155Instance.address, 2)).eq(4), 'Invalid multiple token balance (2)');
            assert((await composableTopDownInstance.balanceOfERC1155(1, sampleERC1155Instance.address, 3)).eq(6), 'Invalid multiple token balance (3)');
            assert(arrayEq(await composableTopDownInstance.balanceOfBatchERC1155([1, 1, 1], sampleERC1155Instance.address, [1, 2, 3]), [2, 4, 6]), 'Invalid multiple token balance (4)');
        });

        it('Should transfer batch', async () => {
            await sampleERC1155InstanceAlice.safeBatchTransferFrom(alice.address, composableTopDownInstance.address, [1, 2, 3], [3, 6, 9], bytesFirstToken);
            await composableTopDownInstance.safeBatchTransferFromERC1155(1, alice.address, sampleERC1155InstanceAlice.address, [1, 2, 3], [1, 2, 3], bytesFirstToken);
            assert(arrayEq(await composableTopDownInstance.balanceOfBatchERC1155([1, 1, 1], sampleERC1155Instance.address, [1, 2, 3]), [2, 4, 6]), 'Invalid multiple token balance (4)');
        });

        it('Should iterate', async () => {
            await sampleERC1155InstanceAlice.safeBatchTransferFrom(alice.address, composableTopDownInstance.address, [1, 2, 3], [3, 6, 9], bytesFirstToken);
            let totalContracts = await composableTopDownInstance.totalERC1155Contracts(1);
            assert(totalContracts.eq(1), 'Invalid number of contracts');
            for (i = 0 ; i < totalContracts.toNumber() ; i ++) {
                let contract = composableTopDownInstance.erc1155ContractByIndex(1, i);
                let totalChildTokens = await composableTopDownInstance.totalERC1155Tokens(1, contract);
                assert(totalChildTokens.eq(3), 'Invalid number of child tokens');
                let childTokens = [];
                for (j = 0 ; j < totalChildTokens.toNumber() ; j ++) {
                    let childToken = await composableTopDownInstance.erc1155TokenByIndex(1, contract, j);
                    childTokens.push(childToken);
                }
                assert(arrayEq(childTokens, [1, 2, 3]), 'Invalid child tokens');
            }
        });


    });

    describe('ERC165', async () => {
        it('Should declare interfaces: ERC165, ERC721, IERC998ERC721TopDown, IERC998ERC721TopDownEnumerable, IERC998ERC20TopDown, IERC998ERC20TopDownEnumerable', async () => {
            assert(await composableTopDownInstance.supportsInterface('0x01ffc9a7'), 'No interface declaration: ERC165');
            assert(await composableTopDownInstance.supportsInterface('0x80ac58cd'), 'No interface declaration: ERC721');
            assert(await composableTopDownInstance.supportsInterface('0x7064387e'), 'No interface declaration: IERC998ERC1155TopDown');
            assert(await composableTopDownInstance.supportsInterface('0x81de020c'), 'No interface declaration: IERC998ERC1155TopDownEnumerable');
            assert(await composableTopDownInstance.supportsInterface('0x4e2312e0'), 'No interface declaration: IERC1155Receiver');
        });
    });

    describe('StateHash', async () => {
        it('Should set state hash (5) erc1155', async () => {
            let tx = await composableTopDownInstance.safeMint(alice.address);  // 1 tokenId
            tx = await tx.wait();
            let stateHash1 = await composableTopDownInstance.stateHash(1);
            const uri = 'https://token-cdn-domain/\\{id\\}.json';
            const sampleERC1155Instance = await SampleERC1155.deploy(uri);
            await sampleERC1155Instance.mint(alice.address, 2, 100);
            const sampleERC1155InstanceAlice = sampleERC1155Instance.connect(alice);

            await sampleERC1155InstanceAlice.safeTransferFrom(alice.address, composableTopDownInstance.address, 2, 100, bytesFirstToken);
            let stateHash2 = await composableTopDownInstance.stateHash(1);
            let expectedStateHash = ethers.utils.solidityKeccak256(["uint256", "uint256", "address", "uint256", "uint256"], [stateHash1, 1, sampleERC1155Instance.address, 2, 100]);
            assert(stateHash2 == expectedStateHash, "Wrong state hash for tokenId 1,");

            await composableTopDownInstance.safeTransferFromERC1155(1, alice.address, sampleERC1155Instance.address, 2, 30, bytesFirstToken);
            let stateHash3 = await composableTopDownInstance.stateHash(1);
            expectedStateHash = ethers.utils.solidityKeccak256(["uint256", "uint256", "address", "uint256", "uint256"], [stateHash2, 1, sampleERC1155Instance.address, 2, 70]);
            assert(stateHash3 == expectedStateHash, "Wrong state hash for tokenId 2,");
        });
        it('Should set state hash (6) batch erc1155', async () => {
            let tx = await composableTopDownInstance.safeMint(alice.address);  // 1 tokenId
            tx = await tx.wait();
            let stateHash1 = await composableTopDownInstance.stateHash(1);
            const uri = 'https://token-cdn-domain/\\{id\\}.json';
            const sampleERC1155Instance = await SampleERC1155.deploy(uri);
            await sampleERC1155Instance.mint(alice.address, 1, 100);
            await sampleERC1155Instance.mint(alice.address, 2, 100);
            const sampleERC1155InstanceAlice = sampleERC1155Instance.connect(alice);

            await sampleERC1155InstanceAlice.safeBatchTransferFrom(alice.address, composableTopDownInstance.address, [1, 2], [100, 100], bytesFirstToken);
            let stateHash2 = await composableTopDownInstance.stateHash(1);
            let expectedStateHash = ethers.utils.solidityKeccak256(["uint256", "uint256", "address", "uint256", "uint256"], [stateHash1, 1, sampleERC1155Instance.address, 1, 100]);
            expectedStateHash = ethers.utils.solidityKeccak256(["uint256", "uint256", "address", "uint256", "uint256"], [expectedStateHash, 1, sampleERC1155Instance.address, 2, 100]);
            assert(stateHash2 == expectedStateHash, "Wrong state hash for tokenId 1,");

            await composableTopDownInstance.safeBatchTransferFromERC1155(1, alice.address, sampleERC1155InstanceAlice.address, [1, 2], [30, 30], bytesFirstToken);
            let stateHash3 = await composableTopDownInstance.stateHash(1);
            expectedStateHash = ethers.utils.solidityKeccak256(["uint256", "uint256", "address", "uint256", "uint256"], [stateHash2, 1, sampleERC1155Instance.address, 1, 70]);
            expectedStateHash = ethers.utils.solidityKeccak256(["uint256", "uint256", "address", "uint256", "uint256"], [expectedStateHash, 1, sampleERC1155Instance.address, 2, 70]);
            assert(stateHash3 == expectedStateHash, "Wrong state hash for tokenId 2,");
        });
    });

    async function setUpTestTokens(nftCount, erc20Count) {
        let nfts = [];
        let erc20s = [];
        for (let i = 0; i < nftCount; i++) {
            nfts.push(await SampleNFT.deploy());
        }

        for (let i = 0; i < erc20Count; i++) {
            erc20s.push(await SampleERC20.deploy(i.toString(), i.toString()));
        }

        return [nfts, erc20s];
    }

    async function safeTransferFromFirstToken() {
        await sampleNFTInstance
        // .connect(alice)
        ['safeTransferFrom(address,address,uint256,bytes)'](
            alice.address,
            composableTopDownInstance.address,
            expectedTokenId,
            bytesFirstToken);
    }
});
