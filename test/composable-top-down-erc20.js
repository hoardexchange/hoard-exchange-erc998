const { assert, expect } = require('chai');
const { ethers } = require("hardhat");

describe('ComposableTopDownERC20', async () => {
    let ComposableTopDown,
        SampleERC20,
        SampleNFT,
        ContractIERC721ReceiverNew,
        ContractIERC721ReceiverOld;

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

        ComposableTopDown = await ethers.getContractFactory("ComposableTopDownERC20Dev");
        SampleERC20 = await ethers.getContractFactory("SampleERC20");
        SampleNFT = await ethers.getContractFactory("SampleNFT");
        ContractIERC721ReceiverNew = await ethers.getContractFactory("ContractIERC721ReceiverNew");
        ContractIERC721ReceiverOld = await ethers.getContractFactory("ContractIERC721ReceiverOld");

        composableTopDownInstance = await ComposableTopDown.deploy();
        await composableTopDownInstance.deployed();
    });


    describe('ERC20 Transfers', async () => {
        const mintTokensAmount = 1000;
        const name = 'SampleERC20';
        const symbol = 'S';
        const transferAmount = mintTokensAmount / 2;
        const secondTransferAmount = transferAmount / 2;

        beforeEach(async () => {
            sampleERC20Instance = await SampleERC20.deploy(name, symbol);

            // mint
            await sampleERC20Instance.mint(alice.address, mintTokensAmount);

            await composableTopDownInstance.safeMint(alice.address);
        });

        it('Should have proper token balance', async () => {
            const aliceBalance = await sampleERC20Instance.balanceOf(alice.address);
            assert(aliceBalance.eq(mintTokensAmount), 'Invalid initial token balance');
        });

        it('Should transfer half the value from ERC20 to Composable', async () => {
            // when:
            await sampleERC20Instance
                .connect(alice)['transfer(address,uint256,bytes)'](
                    composableTopDownInstance.address,
                    transferAmount,
                    bytesFirstToken
                );

            // then:
            const totalERC20Contracts = await composableTopDownInstance.totalERC20Contracts(expectedTokenId);
            assert(totalERC20Contracts.eq(1), 'Invalid total erc20 contracts');

            const balance = await composableTopDownInstance
                .balanceOfERC20(expectedTokenId, sampleERC20Instance.address);
            assert(balance.eq(transferAmount), 'Invalid Composable ERC20 balance');

            const erc20ContractByIndex = await composableTopDownInstance.erc20ContractByIndex(expectedTokenId, 0);
            assert(erc20ContractByIndex === sampleERC20Instance.address, 'Invalid erc20 contract by index');
        });

        it('Should transfer from Composable to bob via transferERC20', async () => {
            // given:
            await sampleERC20Instance
                .connect(alice)['transfer(address,uint256,bytes)'](
                    composableTopDownInstance.address,
                    transferAmount,
                    bytesFirstToken
                );

            // when:
            await composableTopDownInstance
                .connect(alice)
                .transferERC20(
                    expectedTokenId,
                    bob.address,
                    sampleERC20Instance.address,
                    secondTransferAmount
                );

            // then:
            const composableBalance = await composableTopDownInstance
                .balanceOfERC20(expectedTokenId, sampleERC20Instance.address);
            assert(composableBalance.eq(secondTransferAmount), 'Invalid Composable ERC20 balance');

            const bobBalance = await sampleERC20Instance.balanceOf(bob.address);
            assert(bobBalance.eq(secondTransferAmount), 'Invalid bob balance');
        });

        it('Should transfer from Composable to bob via transferERC223', async () => {
            // given:
            await sampleERC20Instance
                .connect(alice)['transfer(address,uint256,bytes)'](
                    composableTopDownInstance.address,
                    transferAmount,
                    bytesFirstToken
                );

            // when:
            await composableTopDownInstance
                .connect(alice)
                .transferERC223(
                    expectedTokenId,
                    bob.address,
                    sampleERC20Instance.address,
                    secondTransferAmount,
                    bytesFirstToken
                );

            // then:
            const composableBalance = await composableTopDownInstance
                .balanceOfERC20(expectedTokenId, sampleERC20Instance.address);
            assert(composableBalance.eq(secondTransferAmount), 'Invalid Composable ERC20 balance');

            const bobBalance = await sampleERC20Instance.balanceOf(bob.address);
            assert(bobBalance.eq(secondTransferAmount), 'Invalid bob balance');
        });

        it('Should transfer everything from Composable to bob via transferERC223', async () => {
            // given:
            await sampleERC20Instance
                .connect(alice)['transfer(address,uint256,bytes)'](
                    composableTopDownInstance.address,
                    transferAmount,
                    bytesFirstToken
                );

            // when:
            await composableTopDownInstance
                .connect(alice)
                .transferERC223(
                    expectedTokenId,
                    bob.address,
                    sampleERC20Instance.address,
                    transferAmount,
                    bytesFirstToken
                );

            // then:
            const composableBalance = await composableTopDownInstance
                .balanceOfERC20(expectedTokenId, sampleERC20Instance.address);
            assert(composableBalance.eq(0), 'Invalid Composable ERC20 balance');

            const bobBalance = await sampleERC20Instance.balanceOf(bob.address);
            assert(bobBalance.eq(transferAmount), 'Invalid bob balance');

            const totalERC20Contracts = await composableTopDownInstance.totalERC20Contracts(expectedTokenId);
            assert(totalERC20Contracts.eq(0), 'Invalid total erc20 contracts');
        });

        it('Should transfer 0 from Composable to bob via transferERC223', async () => {
            // given:
            await sampleERC20Instance
                .connect(alice)['transfer(address,uint256,bytes)'](
                    composableTopDownInstance.address,
                    transferAmount,
                    bytesFirstToken
                );

            // when:
            await composableTopDownInstance
                .connect(alice)
                .transferERC223(
                    expectedTokenId,
                    bob.address,
                    sampleERC20Instance.address,
                    0,
                    bytesFirstToken
                );

            // then:
            const composableBalance = await composableTopDownInstance
                .balanceOfERC20(expectedTokenId, sampleERC20Instance.address);
            assert(composableBalance.eq(transferAmount), 'Invalid Composable ERC20 balance');

            const bobBalance = await sampleERC20Instance.balanceOf(bob.address);
            assert(bobBalance.eq(0), 'Invalid bob balance');
        });

        it('Should get tokens using getERC20', async () => {
            // given:
            await sampleERC20Instance.connect(alice).approve(composableTopDownInstance.address, transferAmount);

            // when:
            await composableTopDownInstance.connect(alice)
                .getERC20(
                    alice.address,
                    expectedTokenId,
                    sampleERC20Instance.address,
                    transferAmount);

            // then:
            const composableBalance = await composableTopDownInstance
                .balanceOfERC20(expectedTokenId, sampleERC20Instance.address);
            assert(composableBalance.eq(transferAmount), 'Invalid Composable ERC20 balance');

            const erc20ComposableBalance = await sampleERC20Instance.balanceOf(composableTopDownInstance.address);
            assert(erc20ComposableBalance.eq(composableBalance), 'Invalid ERC20 Composable balance');
        });

        it('Should get 0 tokens using getERC20', async () => {
            // given:
            await sampleERC20Instance.connect(alice).approve(composableTopDownInstance.address, transferAmount);

            // when:
            await composableTopDownInstance.connect(alice)
                .getERC20(
                    alice.address,
                    expectedTokenId,
                    sampleERC20Instance.address,
                    0);

            // then:
            const composableBalance = await composableTopDownInstance
                .balanceOfERC20(expectedTokenId, sampleERC20Instance.address);
            assert(composableBalance.eq(0), 'Invalid Composable ERC20 balance');

            const erc20ComposableBalance = await sampleERC20Instance.balanceOf(composableTopDownInstance.address);
            assert(erc20ComposableBalance.eq(0), 'Invalid ERC20 Composable balance');
        });

        it('Should revert getERC20 with invalid contract address', async () => {
            const expectedRevertMessage = 'CTD: getERC20 allowance failed';
            await expect(
                composableTopDownInstance
                    .connect(bob)
                    .getERC20(
                        alice.address,
                        expectedTokenId,
                        composableTopDownInstance.address,
                        transferAmount)).to.be.revertedWith(
                            expectedRevertMessage);
        });

        it('Should revert getERC20 allowed address not enough amount', async () => {
            const expectedRevertMessage = 'CTD: getERC20 value greater than remaining';
            // when:
            await expect(
                composableTopDownInstance
                    .connect(bob)
                    .getERC20(
                        alice.address,
                        expectedTokenId,
                        sampleERC20Instance.address,
                        transferAmount)).to.be.revertedWith(
                            expectedRevertMessage);
        });

        it('Should get tokens using getERC20, using bob as approved sender', async () => {
            // given:
            await sampleERC20Instance.connect(alice).approve(bob.address, transferAmount);
            await sampleERC20Instance.connect(alice).approve(composableTopDownInstance.address, transferAmount);

            // when:
            await composableTopDownInstance.connect(bob)
                .getERC20(
                    alice.address,
                    expectedTokenId,
                    sampleERC20Instance.address,
                    transferAmount);

            // then:
            const composableBalance = await composableTopDownInstance
                .balanceOfERC20(expectedTokenId, sampleERC20Instance.address);
            assert(composableBalance.eq(transferAmount), 'Invalid Composable ERC20 balance');

            const erc20ComposableBalance = await sampleERC20Instance.balanceOf(composableTopDownInstance.address);
            assert(erc20ComposableBalance.eq(composableBalance), 'Invalid ERC20 Composable balance');
        });
    });

    describe('Multi Token tests', async () => {
        const mintTokensAmount = 1000;
        const transferAmount = 500;
        const totalTokens = 5;
        const mintedPerNFT = 3;

        beforeEach(async () => {
            await composableTopDownInstance.safeMint(alice.address);
        });

        it('Should return proper totals after addition and removal', async () => {
            // given:
            const [nfts, erc20s] = await setUpTestTokens(totalTokens, totalTokens);

            // when:

            // transfer erc20s
            for (let i = 0; i < erc20s.length; i++) {
                await erc20s[i].mint(alice.address, mintTokensAmount);
                await erc20s[i].connect(alice)['transfer(address,uint256,bytes)'](
                    composableTopDownInstance.address,
                    transferAmount,
                    bytesFirstToken
                );

                const balance = await composableTopDownInstance.balanceOfERC20(expectedTokenId, erc20s[i].address);
                assert(balance.eq(transferAmount), `Invalid balanceOfERC20 on Token ${i}`);
            }

            const totalERC20TokensAdded = await composableTopDownInstance.totalERC20Contracts(expectedTokenId);
            assert(totalERC20TokensAdded.eq(totalTokens), 'Invalid Alice total ERC20 cotracts');

            // remove erc20s
            let tokenERC20Contracts = await composableTopDownInstance.totalERC20Contracts(expectedTokenId);

            for (let i = 0; i < tokenERC20Contracts; i++) {
                const tokenAddress = await composableTopDownInstance.erc20ContractByIndex(expectedTokenId, i);
                const balance = await composableTopDownInstance.balanceOfERC20(expectedTokenId, tokenAddress);

                await composableTopDownInstance.connect(alice).transferERC20(expectedTokenId, alice.address, tokenAddress, balance);
                const nextNumTotalERC20Contracts = await composableTopDownInstance.totalERC20Contracts(expectedTokenId);

                assert(nextNumTotalERC20Contracts.eq(tokenERC20Contracts.sub(1)), `Expected ${tokenERC20Contracts - 1} tokenContracts but got ${nextNumTotalERC20Contracts}`);
                tokenERC20Contracts = nextNumTotalERC20Contracts;
            }
        });
    });

    describe('Between ComposableTopDowns / Gas Usages', async () => {
        beforeEach(async () => {
            secondComposableTopDownInstance = await ComposableTopDown.deploy();

            await composableTopDownInstance.safeMint(alice.address);
            await secondComposableTopDownInstance.safeMint(bob.address);
        });

        describe('Transfer ERC20 from ComposableTopDown to ComposableTopDown', async () => {
            const mintTokensAmount = 1000;
            const name = 'SampleERC20';
            const symbol = 'S';
            const transferAmount = mintTokensAmount / 2;
            const secondTransferAmount = transferAmount / 2;

            beforeEach(async () => {
                sampleERC20Instance = await SampleERC20.deploy(name, symbol);
                // mint
                await sampleERC20Instance.mint(alice.address, mintTokensAmount);

                // transfer to first composable
                await sampleERC20Instance
                    .connect(alice)['transfer(address,uint256,bytes)'](
                        composableTopDownInstance.address,
                        transferAmount,
                        bytesFirstToken
                    );
            });

            it('Should successfully transferERC20 half the amount', async () => {
                // when:
                await composableTopDownInstance.connect(alice)
                    .transferERC20(
                        expectedTokenId,
                        secondComposableTopDownInstance.address,
                        sampleERC20Instance.address,
                        secondTransferAmount
                    );
                const firstComposableBalance = await sampleERC20Instance.balanceOf(composableTopDownInstance.address);
                const secondComposableBalance = await sampleERC20Instance.balanceOf(secondComposableTopDownInstance.address);

                assert(firstComposableBalance.eq(secondComposableBalance), 'Invalid balances');
            });

            it('Should successfully transferERC20 everything', async () => {
                // when:
                await composableTopDownInstance.connect(alice)
                    .transferERC20(
                        expectedTokenId,
                        secondComposableTopDownInstance.address,
                        sampleERC20Instance.address,
                        transferAmount
                    );

                const firstComposableBalance = await sampleERC20Instance.balanceOf(composableTopDownInstance.address);
                const secondComposableBalance = await sampleERC20Instance.balanceOf(secondComposableTopDownInstance.address);

                assert(firstComposableBalance.eq(0), 'Invalid first composable balance');
                assert(secondComposableBalance.eq(transferAmount), 'Invalid second composable balance');
            });

            it('Should successfully transferERC223 half the amount', async () => {
                // when:
                await composableTopDownInstance.connect(alice)
                    .transferERC223(
                        expectedTokenId,
                        secondComposableTopDownInstance.address,
                        sampleERC20Instance.address,
                        secondTransferAmount,
                        bytesFirstToken
                    );

                const firstComposableBalance = await sampleERC20Instance.balanceOf(composableTopDownInstance.address);
                const secondComposableBalance = await sampleERC20Instance.balanceOf(secondComposableTopDownInstance.address);

                assert(firstComposableBalance.eq(secondComposableBalance), 'Invalid balances');
            });

            it('Should successfully transferERC223 everything', async () => {
                // when:
                await composableTopDownInstance.connect(alice)
                    .transferERC223(
                        expectedTokenId,
                        secondComposableTopDownInstance.address,
                        sampleERC20Instance.address,
                        transferAmount,
                        bytesFirstToken
                    );
                const firstComposableBalance = await sampleERC20Instance.balanceOf(composableTopDownInstance.address);
                const secondComposableBalance = await sampleERC20Instance.balanceOf(secondComposableTopDownInstance.address);

                assert(firstComposableBalance.eq(0), 'Invalid first composable balance');
                assert(secondComposableBalance.eq(transferAmount), 'Invalid second composable balance');
            });

            it('Should successfully transferERC223 everything on 5 portions', async () => {
                // given:
                const portion = transferAmount / 5;

                // when:
                for (let i = 0; i < 5; i++) {
                    await composableTopDownInstance.connect(alice)
                        .transferERC223(
                            expectedTokenId,
                            secondComposableTopDownInstance.address,
                            sampleERC20Instance.address,
                            portion,
                            bytesFirstToken
                        );
                }

                const firstComposableBalance = await sampleERC20Instance.balanceOf(composableTopDownInstance.address);
                const secondComposableBalance = await sampleERC20Instance.balanceOf(secondComposableTopDownInstance.address);

                assert(firstComposableBalance.eq(0), 'Invalid first composable balance');
                assert(secondComposableBalance.eq(transferAmount), 'Invalid second composable balance');

                const firstComposableTokenIdBalance = await composableTopDownInstance
                    .balanceOfERC20(expectedTokenId, sampleERC20Instance.address);
                assert(firstComposableTokenIdBalance.eq(0), 'Invalid first composable tokenId balance');

                const secondComposableTokenIdBalance = await secondComposableTopDownInstance
                    .balanceOfERC20(expectedTokenId, sampleERC20Instance.address);
                assert(secondComposableTokenIdBalance.eq(transferAmount), 'Invalid second composable tokenId balance');
            });
        });
    });

    describe('ERC165', async () => {
        it('Should declare interfaces: ERC165, ERC721, IERC998ERC20TopDown, IERC998ERC20TopDownEnumerable', async () => {
            assert(await composableTopDownInstance.supportsInterface('0x01ffc9a7'), 'No interface declaration: ERC165');
            assert(await composableTopDownInstance.supportsInterface('0x80ac58cd'), 'No interface declaration: ERC721');
            assert(await composableTopDownInstance.supportsInterface('0x7294ffed'), 'No interface declaration: IERC998ERC20TopDown');
            assert(await composableTopDownInstance.supportsInterface('0xc5fd96cd'), 'No interface declaration: IERC998ERC20TopDownEnumerable');
            assert(await composableTopDownInstance.supportsInterface('0x4ff33816'), 'No interface declaration: StateHash');
        });
    });

    describe('StateHash', async () => {
        it('Should set state hash (2)', async () => {
            let tx = await composableTopDownInstance.safeMint(alice.address);  // 1 tokenId
            tx = await tx.wait();
            tx = await composableTopDownInstance.safeMint(alice.address);  // 2 tokenId
            tx = await tx.wait();
            const bytesSecondToken = ethers.utils.hexZeroPad('0x2', 20);
            let stateHash11 = await composableTopDownInstance.stateHash(1);
            let stateHash21 = await composableTopDownInstance.stateHash(2);

            tx = await composableTopDownInstance.connect(alice)['safeTransferFrom(address,address,uint256,bytes)']
                    (alice.address,
                        composableTopDownInstance.address,
                        2,
                        bytesFirstToken);
            tx = await tx.wait();
            let stateHash12 = await composableTopDownInstance.stateHash(1);
            assert(stateHash12 != stateHash11, "state hash update (1)");
            let stateHash22 = await composableTopDownInstance.stateHash(2);
            assert(stateHash22 == stateHash21, "state hash update (2)");

            const [nfts, erc20s] = await setUpTestTokens(1, 1);

            tx = await nfts[0].mint721(alice.address, '00');
            tx = await tx.wait();
            tx = await nfts[0].connect(alice)['safeTransferFrom(address,address,uint256,bytes)'](
                        alice.address,
                        composableTopDownInstance.address,
                        1,  //mintedTokenId
                        bytesSecondToken);
            tx = await tx.wait();
            let stateHash13 = await composableTopDownInstance.stateHash(1);
            assert(stateHash13 != stateHash12, "state hash update (3)");
            let stateHash23 = await composableTopDownInstance.stateHash(2);
            assert(stateHash23 == stateHash22, "state hash update (4)");

            await erc20s[0].mint(alice.address, 10);
            await erc20s[0].connect(alice)['transfer(address,uint256,bytes)'](
                    composableTopDownInstance.address,
                    10, //transferAmount
                    bytesSecondToken
                );
            let stateHash14 = await composableTopDownInstance.stateHash(1);
            assert(stateHash14 != stateHash13, "state hash update (5)");
            let stateHash24 = await composableTopDownInstance.stateHash(2);
            assert(stateHash24 == stateHash23, "state hash update (6)");
        });

        it('Should set state hash (4) erc20', async () => {
            let tx = await composableTopDownInstance.safeMint(alice.address);  // 1 tokenId
            tx = await tx.wait();
            let stateHash1 = await composableTopDownInstance.stateHash(1);
            const [nfts, erc20s] = await setUpTestTokens(1, 1);
            await erc20s[0].mint(alice.address, 100);

            await erc20s[0].connect(alice)['transfer(address,uint256,bytes)'](
                    composableTopDownInstance.address,
                    100, // transferAmount
                    bytesFirstToken
                );
            let stateHash2 = await composableTopDownInstance.stateHash(1);
            let expectedStateHash = ethers.utils.solidityKeccak256(["uint256", "uint256", "address", "uint256"], [stateHash1, 1, erc20s[0].address, 100]);
            assert(stateHash2 == expectedStateHash, "Wrong state hash for tokenId 1,");

            tx = await composableTopDownInstance.connect(alice)['transferERC20(uint256,address,address,uint256)']
                    (1, alice.address,
                        erc20s[0].address,
                        30 // erc20 amount
                        );
            tx = await tx.wait();
            let stateHash3 = await composableTopDownInstance.stateHash(1);
            expectedStateHash = ethers.utils.solidityKeccak256(["uint256", "uint256", "address", "uint256"], [stateHash2, 1, erc20s[0].address, 70]);
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
