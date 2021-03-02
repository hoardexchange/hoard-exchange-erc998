const etherlime = require('etherlime-lib');
const ethers = require('ethers');

const ComposableTopDown = require('../build/ComposableTopDown.json');
const SampleERC20 = require('../build/SampleERC20.json');
const SampleNFT = require('../build/SampleNFT.json');

describe('ComposableTopDown', async () => {

    const defaulOverrides = {
        gasLimit: 6720000
    };
    const alice = accounts[1].signer;
    const bob = accounts[2].signer;
    const owner = accounts[9];

    const expectedTokenId = 1;
    const firstChildTokenId = 1;
    const bytesFirstToken = '0x0000000000000000000000000000000000000001';  // todo: fix bytes variable

    const NFTHash = '0x1234';

    beforeEach(async () => {
        deployer = new etherlime.EtherlimeGanacheDeployer(owner.secretKey);
        composableTopDownInstance = await deployer.deploy(
            ComposableTopDown,
            {},
            defaulOverrides
        );
    });

    it('Should deploy ComposableTopDown Contract', async () => {
        assert.isAddress(
            composableTopDownInstance.contractAddress,
            'ComposableTopDownInstance not deployed'
        );
    });


    describe('NFT Transfers', async () => {
        beforeEach(async () => {
            sampleNFTInstance = await deployer.deploy(SampleNFT, {}, defaulOverrides);

            // mint
            await sampleNFTInstance.mint721(alice.address, NFTHash);

            await composableTopDownInstance.mint(alice.address);
        });

        it('Should deploy SampleNFT Contract and mint to alice', async () => {
            assert.isAddress(
                sampleNFTInstance.contractAddress,
                'SampleNFT not deployed'
            );

            const hashTaken = await sampleNFTInstance.hashes(NFTHash);
            assert(hashTaken, 'NFTHash not taken');

            // todo: check that minted to alice
        });

        it('Should safeTransferFrom SampleNFT to Composable', async () => {
            await sampleNFTInstance
                .from(alice)['safeTransferFrom(address,address,uint256,bytes)'](
                    alice.address,
                    composableTopDownInstance.contractAddress,
                    expectedTokenId,
                    bytesFirstToken); //todo: fix bytes variable

            const childExists = await composableTopDownInstance.childExists(sampleNFTInstance.contractAddress, firstChildTokenId);
            assert(childExists, 'Composable does not own SampleNFT');

            const ownerOfChild = await composableTopDownInstance.ownerOfChild(sampleNFTInstance.contractAddress, firstChildTokenId);
            assert(ownerOfChild.parentTokenId.eq(expectedTokenId), 'Invalid parent token id');

            const totalChildContracts = await composableTopDownInstance.totalChildContracts(expectedTokenId);
            assert(totalChildContracts.eq(1), 'Invalid total child contracts');

            const childContractAddress = await composableTopDownInstance.childContractByIndex(expectedTokenId, 0);
            assert(childContractAddress === sampleNFTInstance.contractAddress, 'Invalid child contract address');

            const tokenId = await composableTopDownInstance.childTokenByIndex(expectedTokenId, sampleNFTInstance.contractAddress, 0);
            assert(tokenId.eq(expectedTokenId), 'Invalid token id found when querying child token by index');
        });

        describe('Composable Transfers', async () => {
            beforeEach(async () => {
                await sampleNFTInstance
                    .from(alice)['safeTransferFrom(address,address,uint256,bytes)'](
                        alice.address,
                        composableTopDownInstance.contractAddress,
                        expectedTokenId,
                        bytesFirstToken);
            });

            it('Should revert when trying to transfer unapproved', async () => {
                const expectedRevertMessage = 'ComposableTopDown: _transferFrom msg.sender not approved';
                await assert.revertWith(composableTopDownInstance.transferFrom(alice.address, bob.address, expectedTokenId), expectedRevertMessage);
            });

            it('Should successfully transferFrom', async () => {
                await composableTopDownInstance.from(alice.address).transferFrom(alice.address, bob.address, expectedTokenId);

                const ownerOf = await composableTopDownInstance.ownerOf(expectedTokenId);
                assert(ownerOf === bob.address, 'Invalid owner');
            });

            it('Should successfully return back token', async () => {
                await composableTopDownInstance.from(alice.address).transferFrom(alice.address, bob.address, expectedTokenId);

                await composableTopDownInstance
                    .from(bob.address)['transferChild(uint256,address,address,uint256)'](
                        expectedTokenId,
                        alice.address,
                        sampleNFTInstance.contractAddress,
                        expectedTokenId
                    );

                const owner = await sampleNFTInstance.ownerOf(expectedTokenId);
                assert(owner === alice.address, 'Invalid owner address');

                const totalChildContracts = await composableTopDownInstance.totalChildContracts(expectedTokenId);
                assert(totalChildContracts.eq(0), 'Invalid child contracts length');

                const childExists = await composableTopDownInstance.childExists(sampleNFTInstance.contractAddress, expectedTokenId);
                assert(!childExists, 'child contract exists');
            });

            describe('Between Composables - safeTransferChild', async () => {
                const secondToken = 2;
                const secondChildTokenId = 2;
                const secondNFTHash = '0x5678';
                const bytesSecondToken = '0x0000000000000000000000000000000000000002';

                beforeEach(async () => {
                    await composableTopDownInstance.mint(alice.address);
                    await sampleNFTInstance.mint721(alice.address, secondNFTHash);

                    await sampleNFTInstance
                        .from(alice)['safeTransferFrom(address,address,uint256,bytes)'](
                            alice.address,
                            composableTopDownInstance.contractAddress,
                            secondToken,
                            bytesSecondToken);
                });

                it('Should have successfully transferred secondToken', async () => {
                    const childExists = await composableTopDownInstance.childExists(sampleNFTInstance.contractAddress, secondChildTokenId);
                    assert(childExists, 'Composable does not own SampleNFT');

                    const ownerOfChild = await composableTopDownInstance.ownerOfChild(sampleNFTInstance.contractAddress, secondChildTokenId);
                    assert(ownerOfChild.parentTokenId.eq(secondToken), 'Invalid parent token id');

                    const totalChildContracts = await composableTopDownInstance.totalChildContracts(secondToken);
                    assert(totalChildContracts.eq(1), 'Invalid total child contracts');

                    const childContractAddress = await composableTopDownInstance.childContractByIndex(secondToken, 0);
                    assert(childContractAddress === sampleNFTInstance.contractAddress, 'Invalid child contract address');

                    const tokenId = await composableTopDownInstance.childTokenByIndex(secondToken, sampleNFTInstance.contractAddress, 0);
                    assert(tokenId.eq(secondToken), 'Invalid token id found when querying child token by index');
                });

                it('Should successfully safeTransferChild', async () => {
                    await composableTopDownInstance
                        .from(alice.address)['safeTransferChild(uint256,address,address,uint256,bytes)'](
                            secondToken,
                            composableTopDownInstance.contractAddress,
                            sampleNFTInstance.contractAddress,
                            secondToken,
                            bytesFirstToken
                        );

                    const contractByIndex = await composableTopDownInstance.childContractByIndex(expectedTokenId, 0);
                    assert(contractByIndex === sampleNFTInstance.contractAddress, 'Invalid child contract by index');

                    const childExists = await composableTopDownInstance.childExists(sampleNFTInstance.contractAddress, secondToken);
                    assert(childExists, 'SecondToken does not exist as child to SampleNFT');

                    const totalChildContracts = await composableTopDownInstance.totalChildContracts(expectedTokenId);
                    assert(totalChildContracts.eq(1), 'Invalid total child contracts');

                    const owner = await sampleNFTInstance.ownerOf(secondToken);
                    assert(owner === composableTopDownInstance.contractAddress, 'ComposableTopDown is not owner SecondToken');

                    const ownerOfChild = await composableTopDownInstance.ownerOfChild(sampleNFTInstance.contractAddress, secondToken);
                    assert(ownerOfChild.parentTokenId.eq(expectedTokenId), 'Invalid SampleNFT child token 2 owner');
                });
            });
        });
    });


    describe('ERC20 Transfers', async () => {
        const mintTokensAmount = 1000;
        const name = "SampleERC20";
        const symbol = "S";

        beforeEach(async () => {
            sampleERC20Instance = await deployer.deploy(SampleERC20, {}, name, symbol);

            // mint
            await sampleERC20Instance.mint(alice.address, mintTokensAmount);

            await composableTopDownInstance.mint(alice.address);
        });

        it('Should have proper token balance', async () => {
            const aliceBalance = await sampleERC20Instance.balanceOf(alice.address);
            assert(aliceBalance.eq(mintTokensAmount), 'Invalid initial token balance');
        });

        it('Should transfer half the value from ERC20 to Composable', async () => {
            // todo:
        });

    });
});