const etherlime = require('etherlime-lib');
const ethers = require('ethers');

const ComposableTopDown = require('../build/ComposableTopDown.json');
const SampleERC20 = require('../build/SampleERC20.json');
const SampleNFT = require('../build/SampleNFT.json');

describe('ComposableTopDown', async () => {
    const alice = accounts[1].signer;
    const bob = accounts[2].signer;
    const owner = accounts[9];
    const nonUsed = accounts[8].signer;
    const zeroAddress = "0x0000000000000000000000000000000000000000";

    const expectedTokenId = 1;
    const firstChildTokenId = 1;
    const aliceBalance = 1;
    const bytesFirstToken = '0x0000000000000000000000000000000000000001';  // todo: fix bytes variable

    const NFTHash = '0x1234';

    beforeEach(async () => {
        deployer = new etherlime.EtherlimeGanacheDeployer(owner.secretKey);
        composableTopDownInstance = await deployer.deploy(
            ComposableTopDown,
            {}
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
            sampleNFTInstance = await deployer.deploy(SampleNFT, {});

            // mint
            await sampleNFTInstance.mint721(alice.address, NFTHash);

            await composableTopDownInstance.mint(alice.address);
        });

        it('Should deploy SampleNFT Contract and mint to alice', async () => {
            // then:
            assert.isAddress(
                sampleNFTInstance.contractAddress,
                'SampleNFT not deployed'
            );

            const hashTaken = await sampleNFTInstance.hashes(NFTHash);
            assert(hashTaken, 'NFTHash not taken');

            const balance = await composableTopDownInstance.balanceOf(alice.address);
            assert(balance.eq(aliceBalance), 'Invalid alice balance');

            // todo: check that minted to alice
        });

        it('Should safeTransferFrom SampleNFT to Composable', async () => {
            // when:
            await sampleNFTInstance
                .from(alice)['safeTransferFrom(address,address,uint256,bytes)'](
                    alice.address,
                    composableTopDownInstance.contractAddress,
                    expectedTokenId,
                    bytesFirstToken); //todo: fix bytes variable

            // then:
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

        it('Should revert when trying to get balanceOf zero address', async () => {
            const expectedRevertMessage = 'ComposableTopDown: balance of zero address';
            await assert.revertWith(composableTopDownInstance.balanceOf(zeroAddress), expectedRevertMessage);
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

            it('Should revert when trying to transfer from zero address', async () => {
                const expectedRevertMessage = 'ComposableTopDown: _transferFrom _from zero address';
                await assert.revertWith(composableTopDownInstance.transferFrom(zeroAddress, bob.address, expectedTokenId), expectedRevertMessage);
            });

            it('Should revert when trying to transfer from not owner', async () => {
                const expectedRevertMessage = 'ComposableTopDown: _transferFrom _from not owner';
                await assert.revertWith(composableTopDownInstance.transferFrom(nonUsed.address, bob.address, expectedTokenId), expectedRevertMessage);
            });

            it('Should revert when trying to transfer to zero address', async () => {
                const expectedRevertMessage = 'ComposableTopDown: _transferFrom _to zero address';
                await assert.revertWith(composableTopDownInstance.transferFrom(alice.address, zeroAddress, expectedTokenId), expectedRevertMessage);
            });

            it('Should successfully transferFrom', async () => {
                // when:
                await composableTopDownInstance.from(alice.address).transferFrom(alice.address, bob.address, expectedTokenId);

                // then:
                const ownerOf = await composableTopDownInstance.ownerOf(expectedTokenId);
                assert(ownerOf === bob.address, 'Invalid owner');
            });

            it('Should successfully return back token', async () => {
                // given:
                await composableTopDownInstance.from(alice.address).transferFrom(alice.address, bob.address, expectedTokenId);

                // when:
                await composableTopDownInstance
                    .from(bob.address)['transferChild(uint256,address,address,uint256)'](
                        expectedTokenId,
                        alice.address,
                        sampleNFTInstance.contractAddress,
                        expectedTokenId
                    );

                // then:
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
                    // then:
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
                    // when:
                    await composableTopDownInstance
                        .from(alice.address)['safeTransferChild(uint256,address,address,uint256,bytes)'](
                            secondToken,
                            composableTopDownInstance.contractAddress,
                            sampleNFTInstance.contractAddress,
                            secondToken,
                            bytesFirstToken
                        );

                    // then:
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
        const transferAmount = mintTokensAmount / 2;
        const secondTransferAmount = transferAmount / 2;

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
            // when:
            await sampleERC20Instance
                .from(alice.address)['transfer(address,uint256,bytes)'](
                    composableTopDownInstance.contractAddress,
                    transferAmount,
                    bytesFirstToken
                );

            // then:
            const totalERC20Contracts = await composableTopDownInstance.totalERC20Contracts(expectedTokenId);
            assert(totalERC20Contracts.eq(1), 'Invalid total erc20 contracts');

            const balance = await composableTopDownInstance
                .balanceOfERC20(expectedTokenId, sampleERC20Instance.contractAddress);
            assert(balance.eq(transferAmount), 'Invalid Composable ERC20 balance');
        });

        it('Should transfer from Composable to bob', async () => {
            // given:
            await sampleERC20Instance
                .from(alice.address)['transfer(address,uint256,bytes)'](
                    composableTopDownInstance.contractAddress,
                    transferAmount,
                    bytesFirstToken
                );

            // when:
            await composableTopDownInstance
                .from(alice.address)['transferERC20(uint256,address,address,uint256)'](
                    expectedTokenId,
                    bob.address,
                    sampleERC20Instance.contractAddress,
                    secondTransferAmount
                );

            // then:
            const composableBalance = await composableTopDownInstance
                .balanceOfERC20(expectedTokenId, sampleERC20Instance.contractAddress);
            assert(composableBalance.eq(secondTransferAmount), 'Invalid Composable ERC20 balance');

            const bobBalance = await sampleERC20Instance.balanceOf(bob.address);
            assert(bobBalance.eq(secondTransferAmount), 'Invalid bob balance');
        });
    });
});