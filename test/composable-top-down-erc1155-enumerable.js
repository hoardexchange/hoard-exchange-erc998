const { assert, expect } = require('chai');
const { ethers } = require("hardhat");

describe('ComposableTopDownERC1155Enumerable', async () => {
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

        ComposableTopDown = await ethers.getContractFactory("ComposableTopDownERC1155EnumerableDev");
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
        it('Should declare interfaces: IERC998ERC1155TopDown, IERC998ERC1155TopDownEnumerable', async () => {
            assert(await composableTopDownInstance.supportsInterface('0x7064387e'), 'No interface declaration: IERC998ERC1155TopDown');
            assert(await composableTopDownInstance.supportsInterface('0x81de020c'), 'No interface declaration: IERC998ERC1155TopDownEnumerable');
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
