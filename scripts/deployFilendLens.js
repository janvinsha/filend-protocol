const main = async () => {
  const filendLensFactory = await hre.ethers.getContractFactory("FilendLens");
  const filendLens = await filendLensFactory
    .deploy
    // //admin_
    // "0x659CE0FC2499E1Fa14d30F5CD88aD058ba490e39"
    ();
  await filendLens.deployed();
  console.log("FilendLens Contract deployed to:", filendLens.address);
};

const runMain = async () => {
  try {
    await main();
    process.exit(0);
  } catch (error) {
    console.log(error);
    process.exit(1);
  }
};

runMain();
